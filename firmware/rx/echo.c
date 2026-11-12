/* UWAC receive server: one 4-byte big-endian sample count followed by signed
 * 16-bit little-endian samples. The FPGA captures automatically; DMA and
 * lwIP are serviced without blocking. Hardware errors require PL/DMA reset. */
#include <stdint.h>
#include "lwip/err.h"
#include "lwip/tcp.h"
#include "lwip/pbuf.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xiltimer.h"

#define RX_PORT 6002U
#define DMA_BASE XPAR_AXI_DMA_0_BASEADDR
#define CTRL_BASE XPAR_PS_CTRL_0_BASEADDR
#define CTRL_CLEAR 0x00U
#define CTRL_THRESHOLD 0x04U
#define CTRL_ENERGY_LO 0x08U
#define CTRL_ENERGY_HI 0x0cU
#define CTRL_STATUS 0x10U
#define CTRL_SAMPLES 0x14U
#define CTRL_SEQUENCE 0x1cU
#define CTRL_CONFIG_APPLY 0x20U
#define CTRL_CONFIG_GEN 0x24U
#define CTRL_ACTIVE_THRESHOLD 0x28U
#define CTRL_ACTIVE_ENERGY_LO 0x2cU
#define CTRL_ACTIVE_ENERGY_HI 0x30U
#define CTRL_CONFIG_ID 0x34U
#define CONFIG_ID 0x52584331U
#define CONFIG_BYTES 12U
#define CONFIG_TIMEOUT_MS 30000U
#define PL_BUSY 0x01U
#define PL_DONE 0x02U
#define PL_ERRORS 0x1cU
#define RX_THRESHOLD_Q15 6554U
#define RX_MIN_ENERGY 100000U
#define SLOT_COUNT 2U
#define SLOT_BYTES (24U * 1024U * 1024U)
#define TCP_CHUNK 4096U
#define PAIR_WAIT_MS 1000U

/* Linker-owned, isolated, cache-line aligned DDR buffers. */
static unsigned char buffer[SLOT_COUNT][SLOT_BYTES] __attribute__((aligned(64)));
typedef enum { SLOT_FREE, SLOT_DMA, SLOT_READY, SLOT_SENDING } slot_state;
typedef struct { slot_state state; uint32_t bytes, samples, seq; } slot_info;
static slot_info slots[SLOT_COUNT];
static XAxiDma dma;
static struct tcp_pcb *client;
static int capture_slot=-1, send_slot=-1, faulted=0, header_queued=0, waiting_pl=0;
static int startup_recovery=0;
static unsigned char config_buf[CONFIG_BYTES];
static unsigned config_pos, config_state;
/* 0=request, 1=issue, 2=wait apply, 3=wait quiet, 4=ready, 5=failed. */
static uint32_t config_threshold, config_energy_lo, config_energy_hi, config_gen;
static XTime config_started;
static uint32_t last_seq, send_offset, dropped;
static XTime wait_started;

static uint32_t ctrl_read(unsigned off) { return Xil_In32(CTRL_BASE+off); }
static void ctrl_write(unsigned off, uint32_t v) { Xil_Out32(CTRL_BASE+off,v); }
static uint64_t elapsed_ms(XTime start) {
    XTime now; XTime_GetTime(&now);
    return ((uint64_t)(now-start)*1000ULL)/COUNTS_PER_SECOND;
}
static void release_queued(void) {
    unsigned i;
    for(i=0;i<SLOT_COUNT;i++)
        if(slots[i].state==SLOT_READY || slots[i].state==SLOT_SENDING) slots[i].state=SLOT_FREE;
    send_slot=-1; header_queued=0; send_offset=0;
}
static void abort_client(void) {
    struct tcp_pcb *p=client;
    client=NULL; config_state=0; config_pos=0; release_queued();
    if(p) { tcp_arg(p,NULL); tcp_recv(p,NULL); tcp_err(p,NULL); tcp_sent(p,NULL); tcp_abort(p); }
}
static void hardware_fault(const char *reason, uint32_t sr, uint32_t status) {
    if(faulted) return;
    faulted=1;
    xil_printf("RX FAULT: %s DMA_SR=0x%08x PL=0x%08x; reset PL and DMA before retry\r\n",
               reason,(unsigned int)sr,(unsigned int)status);
    abort_client();
}
static void connection_error(void *arg, err_t err) {
    (void)arg; (void)err; client=NULL; config_state=0; config_pos=0; release_queued();
    xil_printf("TCP client disconnected\r\n");
}
static err_t received(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err) {
    (void)arg;
    if(!p) {
        client=NULL; config_state=0; config_pos=0; release_queued(); tcp_arg(pcb,NULL); tcp_err(pcb,NULL); tcp_recv(pcb,NULL);
        if(tcp_close(pcb)!=ERR_OK) { tcp_abort(pcb); return ERR_ABRT; }
        xil_printf("TCP client closed\r\n"); return ERR_OK;
    }
    if(err!=ERR_OK) { pbuf_free(p); return err; }
    {
        struct pbuf *q; unsigned i; int invalid=0;
        for(q=p;q;q=q->next) {
            const unsigned char *src=(const unsigned char *)q->payload;
            for(i=0;i<q->len;i++) {
                if(config_state!=0 || config_pos>=CONFIG_BYTES) { invalid=1; break; }
                config_buf[config_pos++]=src[i];
                if(config_pos==CONFIG_BYTES) {
                    if(config_buf[0]!='R' || config_buf[1]!='X' || config_buf[2]!='C' ||
                       config_buf[3]!='1' || config_buf[11]!=0) { invalid=1; break; }
                    config_threshold=((uint32_t)config_buf[4]<<8)|config_buf[5];
                    config_energy_hi=config_buf[6];
                    config_energy_lo=((uint32_t)config_buf[7]<<24)|((uint32_t)config_buf[8]<<16)|
                                     ((uint32_t)config_buf[9]<<8)|config_buf[10];
                    if(config_threshold==0 || config_threshold>32768U) { invalid=1; break; }
                    config_state=1; XTime_GetTime(&config_started);
                }
            }
            if(invalid) break;
        }
        tcp_recved(pcb,p->tot_len); pbuf_free(p);
        if(invalid) { xil_printf("Invalid RX configuration request\r\n"); abort_client(); return ERR_ABRT; }
    }
    return ERR_OK;
}
static err_t accepted(void *arg, struct tcp_pcb *pcb, err_t err) {
    (void)arg;
    if(err!=ERR_OK || !pcb) return err;
    if(client || faulted || startup_recovery) { tcp_abort(pcb); return ERR_ABRT; }
    client=pcb; config_state=0; config_pos=0; tcp_arg(pcb,NULL); tcp_recv(pcb,received); tcp_err(pcb,connection_error);
    xil_printf("TCP MATLAB client connected\r\n"); return ERR_OK;
}
void print_app_header(void) {
    xil_printf("\r\nUWAC RX TCP port %u: u32be count + int16le samples\r\n",(unsigned)RX_PORT);
}

static int submit_dma(void) {
    unsigned i;
    for(i=0;i<SLOT_COUNT;i++) if(slots[i].state==SLOT_FREE) {
        /* RX buffers are not modified by CPU and each occupies whole lines. */
        Xil_DCacheInvalidateRange((UINTPTR)buffer[i],SLOT_BYTES);
        /* Interrupt delivery is disabled, but IOC status still records TLAST completion. */
        XAxiDma_IntrAckIrq(&dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
        slots[i].state=SLOT_DMA; capture_slot=(int)i;
        if(XAxiDma_SimpleTransfer(&dma,(UINTPTR)buffer[i],SLOT_BYTES,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS) {
            slots[i].state=SLOT_FREE; capture_slot=-1; return -1;
        }
        return 1;
    }
    return 0;
}
int start_application(void) {
    XAxiDma_Config *cfg; struct tcp_pcb *listener; uint32_t status, seq_check;
#ifdef SDT
    cfg=XAxiDma_LookupConfig(DMA_BASE);
#else
    cfg=XAxiDma_LookupConfigBaseAddr(DMA_BASE);
#endif
    if(!cfg || XAxiDma_CfgInitialize(&dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(&dma) || !dma.HasS2Mm) {
        xil_printf("RX DMA init failed or hardware is not Simple S2MM\r\n"); return -1;
    }
    if(dma.RxBdRing[0].MaxTransferLen<SLOT_BYTES) {
        xil_printf("RX DMA length register too small for buffer\r\n"); return -1;
    }
    XAxiDma_IntrDisable(&dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    last_seq=ctrl_read(CTRL_SEQUENCE);
    status=ctrl_read(CTRL_STATUS);
    seq_check=ctrl_read(CTRL_SEQUENCE);
    if(seq_check!=last_seq) {
        xil_printf("RX completed during initialization; reset PL/FIFO and retry without a signal\r\n");
        return -1;
    }
    if(status&(PL_DONE|PL_ERRORS)) {
        xil_printf("RX has stale completed/error status: PL=0x%08x; reset PL/FIFO and retry\r\n",(unsigned)status);
        return -1;
    }
    /* MATLAB supplies the capture settings after connecting. */
    startup_recovery=((status&PL_BUSY)!=0);
    listener=tcp_new_ip_type(IPADDR_TYPE_ANY);
    if(!listener) { xil_printf("TCP allocation failed\r\n"); return -1; }
    if(tcp_bind(listener,IP_ANY_TYPE,RX_PORT)!=ERR_OK) {
        xil_printf("TCP bind failed\r\n"); tcp_close(listener); return -1;
    }
    listener=tcp_listen(listener);
    if(!listener) { xil_printf("TCP listen failed\r\n"); return -1; }
    tcp_accept(listener,accepted);
    if(submit_dma()!=1) { xil_printf("Initial DMA submit failed\r\n"); return -1; }
    if(startup_recovery)
        xil_printf("RX startup: PL already capturing; DMA will drain and discard this frame. Please wait for RX ready.\r\n");
    else {
        xil_printf("RX ready: DMA buffer %u bytes, threshold=%u, min energy=%u\r\n",
          (unsigned)SLOT_BYTES,(unsigned)ctrl_read(CTRL_THRESHOLD),(unsigned)ctrl_read(CTRL_ENERGY_LO));
        xil_printf("Connect MATLAB before transmitting; no-client frames are discarded.\r\n");
    }
    return 0;
}

static void service_dma(void) {
    uint32_t sr,status,seq,seq2,n,bytes;
    int recovery_finished=0;
    sr=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_RX_OFFSET+XAXIDMA_SR_OFFSET);
    status=ctrl_read(CTRL_STATUS);
    if(sr&XAXIDMA_ERR_ALL_MASK) { hardware_fault("DMA error",sr,status); return; }
    if(status&0x10U) { hardware_fault("processing overrun",sr,status); return; }
    if(capture_slot>=0 && (sr&XAXIDMA_IRQ_IOC_MASK) && (sr&XAXIDMA_IDLE_MASK)) {
        seq=ctrl_read(CTRL_SEQUENCE);
        if(seq==last_seq) {
            if(!waiting_pl) { waiting_pl=1; XTime_GetTime(&wait_started); }
            else if(elapsed_ms(wait_started)>PAIR_WAIT_MS) hardware_fault("DMA complete without PL completion",sr,status);
            return;
        }
        waiting_pl=0;
        n=ctrl_read(CTRL_SAMPLES); status=ctrl_read(CTRL_STATUS); seq2=ctrl_read(CTRL_SEQUENCE);
        bytes=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_RX_OFFSET+XAXIDMA_BUFFLEN_OFFSET);
        if(startup_recovery) {
            /* A startup frame may be partial or already overflowed while DMA
             * was offline. Never deliver it to MATLAB; wait for its TLAST. */
            if(seq2!=seq || seq!=last_seq+1U || !(status&PL_DONE) || bytes==0 || bytes>SLOT_BYTES) {
                hardware_fault("startup recovery could not pair DMA and PL",sr,status); return;
            }
            last_seq=seq; ctrl_write(CTRL_CLEAR,1);
            slots[capture_slot].state=SLOT_FREE; capture_slot=-1; startup_recovery=0;
            recovery_finished=1;
            xil_printf("Discarded startup capture (%u bytes, PL=0x%08x).\r\n",(unsigned)bytes,(unsigned)status);
            /* Re-arm DMA below before declaring readiness. */
        } else {
        if(seq2!=seq || seq!=last_seq+1U || !(status&PL_DONE) ||
           (status&PL_ERRORS) || bytes==0 || bytes>SLOT_BYTES || (bytes&1U) || n!=bytes/2U) {
            xil_printf("RX mismatch: seq=%u previous=%u samples=%u bytes=%u\r\n",
                (unsigned)seq,(unsigned)last_seq,(unsigned)n,(unsigned)bytes);
            hardware_fault("frame integrity/status",sr,status); return;
        }
        Xil_DCacheInvalidateRange((UINTPTR)buffer[capture_slot],bytes);
        slots[capture_slot].bytes=bytes; slots[capture_slot].samples=n; slots[capture_slot].seq=seq;
        last_seq=seq; ctrl_write(CTRL_CLEAR,1);
        if(client && config_state==4) {
            slots[capture_slot].state=SLOT_READY;
            xil_printf("RX frame %u: %u samples (%u bytes)\r\n",(unsigned)seq,(unsigned)n,(unsigned)bytes);
        } else { slots[capture_slot].state=SLOT_FREE; dropped++; }
        capture_slot=-1;
        }
    }
    if(capture_slot<0 && !faulted) {
        int submitted=submit_dma();
        if(submitted<0) hardware_fault("DMA submit",sr,status);
        else if(submitted==0 && (ctrl_read(CTRL_STATUS)&PL_BUSY))
            hardware_fault("no free DDR buffer for next capture",sr,status);
        else if(submitted>0 && recovery_finished)
            xil_printf("RX ready: startup frame discarded; DMA ready for next frame.\r\n");
    }
}
/* RXC1 + threshold u16 BE + min energy u40 BE + reserved byte.
 * RXA1 + status byte precedes all sample frames. */
static void config_reply(unsigned char status) {
    unsigned char response[5]={'R','X','A','1',status}; err_t e;
    if(tcp_sndbuf(client)<sizeof(response)) return;
    e=tcp_write(client,response,sizeof(response),TCP_WRITE_FLAG_COPY);
    if(e==ERR_MEM) return;
    if(e!=ERR_OK) { abort_client(); return; }
    tcp_output(client);
    if(status==0) {
        config_state=4;
        xil_printf("RX settings active: Q15=%u energy_hi=%u energy_lo=%u; ready\r\n",
            (unsigned)config_threshold,(unsigned)config_energy_hi,(unsigned)config_energy_lo);
    } else { config_state=5; xil_printf("RX configuration failed: %u\r\n",(unsigned)status); }
}
static void service_config(void) {
    uint32_t status, seq;
    if(!client || config_state==0 || config_state>=4) return;
    if(config_state==1) {
        /* The legacy register map returns zero for this address: never write
         * the apply register until the updated control IP is present. */
        if(ctrl_read(CTRL_CONFIG_ID)!=CONFIG_ID) { config_reply(1); return; }
        config_gen=ctrl_read(CTRL_CONFIG_GEN);
        ctrl_write(CTRL_THRESHOLD,config_threshold);
        ctrl_write(CTRL_ENERGY_LO,config_energy_lo);
        ctrl_write(CTRL_ENERGY_HI,config_energy_hi);
        ctrl_write(CTRL_CONFIG_APPLY,1);
        config_state=2;
    }
    if(config_state==2 && ctrl_read(CTRL_CONFIG_GEN)!=config_gen) {
        if(ctrl_read(CTRL_ACTIVE_THRESHOLD)!=config_threshold ||
           ctrl_read(CTRL_ACTIVE_ENERGY_LO)!=config_energy_lo ||
           ctrl_read(CTRL_ACTIVE_ENERGY_HI)!=config_energy_hi) { config_reply(2); return; }
        config_state=3;
    }
    if(config_state==3) {
        /* Drain any capture begun before the configuration took effect. */
        seq=ctrl_read(CTRL_SEQUENCE); status=ctrl_read(CTRL_STATUS);
        if(!(status&(PL_BUSY|PL_DONE|PL_ERRORS)) && seq==last_seq && capture_slot>=0) {
            config_reply(0); return;
        }
    }
    if(config_state<4 && elapsed_ms(config_started)>CONFIG_TIMEOUT_MS) config_reply(3);
}
static void service_tcp(void) {
    unsigned i,rounds;
    if(!client || faulted || config_state!=4) return;
    if(send_slot<0) {
        for(i=0;i<SLOT_COUNT;i++) if(slots[i].state==SLOT_READY &&
             (send_slot<0 || slots[i].seq<slots[send_slot].seq)) send_slot=(int)i;
        if(send_slot<0) return;
        slots[send_slot].state=SLOT_SENDING; header_queued=0; send_offset=0;
    }
    if(!header_queued) {
        uint32_t n=slots[send_slot].samples;
        unsigned char header[4]={(unsigned char)(n>>24),(unsigned char)(n>>16),(unsigned char)(n>>8),(unsigned char)n};
        err_t e;
        if(tcp_sndbuf(client)<4) return;
        e=tcp_write(client,header,4,TCP_WRITE_FLAG_COPY);
        if(e==ERR_MEM) return;
        if(e!=ERR_OK) { abort_client(); return; }
        header_queued=1;
    }
    for(rounds=0;rounds<4 && client && send_offset<slots[send_slot].bytes;rounds++) {
        uint32_t n=slots[send_slot].bytes-send_offset;
        u16_t available=tcp_sndbuf(client); err_t e;
        if(n>TCP_CHUNK) n=TCP_CHUNK;
        if(n>available) n=available;
        if(n==0) break;
        e=tcp_write(client,buffer[send_slot]+send_offset,(u16_t)n,TCP_WRITE_FLAG_COPY);
        if(e==ERR_MEM) break;
        if(e!=ERR_OK) { abort_client(); return; }
        send_offset+=n;
    }
    if(client) tcp_output(client);
    if(client && send_offset==slots[send_slot].bytes) {
        xil_printf("RX frame %u queued to TCP\r\n",(unsigned)slots[send_slot].seq);
        slots[send_slot].state=SLOT_FREE; send_slot=-1; header_queued=0; send_offset=0;
    }
}
int transfer_data(void) {
    if(!faulted) service_dma();
    if(!faulted) service_config();
    if(!faulted) service_tcp();
    return 0;
}
