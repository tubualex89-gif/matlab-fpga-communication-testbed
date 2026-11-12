/* TCP waveform receiver: 4-byte big-endian sample count, then N int16 LE samples.
 * One frame at a time; reply one status byte. Hardware faults require reset. */
#include <stdint.h>
#include <string.h>
#include "lwip/err.h"
#include "lwip/tcp.h"
#include "lwip/pbuf.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xiltimer.h"
#include "xil_printf.h"

#define SERVER_PORT 6001U
#define MAX_SAMPLES 10000000U
#define SAMPLE_BYTES 2U
#define CTRL_BASE 0x43C10000U
#define GPIO_BASE XPAR_AXI_GPIO_0_BASEADDR
#define DMA_BASE XPAR_AXI_DMA_0_BASEADDR
#define GPIO_DATA_OFFSET 0U
#define GPIO_TRI_OFFSET 4U
#define STATUS_BUSY 1U
#define STATUS_DONE 2U
#define STATUS_UNDERFLOW 4U
#define STATUS_ZERO_LEN 8U
#define DMA_ERROR_MASK XAXIDMA_ERR_ALL_MASK
#define PREFILL_DELAY_MS 20U /* no FIFO occupancy signal: provisional, not a guarantee */
#define ACCEPT_TIMEOUT_MS 1000U
#define EXTRA_SEND_TIMEOUT_MS 3000U
#define FINAL_DAC_SETTLE_MS 1U

/* Static storage is reserved by the linker in DDR and cache-line aligned. */
static unsigned char waveform[MAX_SAMPLES * SAMPLE_BYTES] __attribute__((aligned(64)));
static XAxiDma dma;
static struct tcp_pcb *client;
typedef enum { WAIT_HEADER, RECV_DATA, PREFILL, WAIT_BUSY, TRANSMIT, FINAL_HOLD, RESPOND, LOCKED } state_t;
static state_t state = WAIT_HEADER;
static unsigned char header[4], response;
static uint32_t header_bytes, sample_count, received_bytes, payload_bytes;
static XTime started;
static int hw_fault, close_after_response;

static uint64_t elapsed_ms(void) {
    XTime now; XTime_GetTime(&now);
    return ((uint64_t)(now - started) * 1000ULL) / COUNTS_PER_SECOND;
}
static void restart_input(void) { header_bytes=0; received_bytes=0; sample_count=0; payload_bytes=0; state=WAIT_HEADER; }
static void send_result(unsigned char code, int close_connection) {
    response=code; close_after_response=close_connection; state=RESPOND;
    xil_printf("Result status %d%s\r\n", (int)code, hw_fault ? " (reset required)" : "");
}
static void connection_error(void *arg, err_t err) {
    (void)arg; (void)err; client=NULL;
    if (state==PREFILL || state==WAIT_BUSY || state==TRANSMIT || state==FINAL_HOLD) hw_fault=1;
    state = hw_fault ? LOCKED : WAIT_HEADER;
    header_bytes=0; received_bytes=0;
}
static err_t received(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err) {
    struct pbuf *q;
    (void)arg;
    if (!p) {
        tcp_arg(pcb,NULL); tcp_recv(pcb,NULL); tcp_err(pcb,NULL);
        if (state==PREFILL || state==WAIT_BUSY || state==TRANSMIT || state==FINAL_HOLD) hw_fault=1;
        client=NULL; state=hw_fault ? LOCKED : WAIT_HEADER;
        if (tcp_close(pcb)!=ERR_OK) { tcp_abort(pcb); return ERR_ABRT; }
        return ERR_OK;
    }
    if (err != ERR_OK) { pbuf_free(p); return err; }
    if (state!=WAIT_HEADER && state!=RECV_DATA) {
        pbuf_free(p); tcp_abort(pcb); return ERR_ABRT;
    }
    for (q=p; q; q=q->next) {
        const unsigned char *buf=(const unsigned char *)q->payload;
        unsigned int off=0;
        while (off<q->len) {
            if (state==WAIT_HEADER) {
                header[header_bytes++]=buf[off++];
                if (header_bytes==4) {
                    sample_count=((uint32_t)header[0]<<24)|((uint32_t)header[1]<<16)|((uint32_t)header[2]<<8)|header[3];
                    if (sample_count==0 || sample_count>MAX_SAMPLES || sample_count > (dma.TxBdRing.MaxTransferLen / SAMPLE_BYTES)) {
                        unsigned char code = (sample_count==0 || sample_count>MAX_SAMPLES) ? 1 : 5;
                        tcp_recved(pcb, p->tot_len);
                        pbuf_free(p);
                        send_result(code,1);
                        return ERR_OK;
                    }
                    payload_bytes=sample_count*SAMPLE_BYTES;
                    xil_printf("Receiving %d samples, %d bytes\r\n", (int)sample_count, (int)payload_bytes);
                    received_bytes=0; state=RECV_DATA;
                }
            } else if (state==RECV_DATA) {
                uint32_t available=q->len-off, remaining=payload_bytes-received_bytes;
                uint32_t count=available<remaining ? available : remaining;
                memcpy(waveform+received_bytes,buf+off,count);
                off+=count; received_bytes+=count;
                if (received_bytes==payload_bytes) {
                    /* A second frame before a reply is a protocol violation. */
                    if (off<q->len || q->next) { pbuf_free(p); tcp_abort(pcb); return ERR_ABRT; }
                    state=PREFILL;
                    XTime_GetTime(&started);
                }
            } else { pbuf_free(p); tcp_abort(pcb); return ERR_ABRT; }
        }
    }
    tcp_recved(pcb,p->tot_len);
    pbuf_free(p);
    return ERR_OK;
}
static err_t accepted(void *arg, struct tcp_pcb *pcb, err_t err) {
    (void)arg; (void)err;
    if (client || hw_fault) { tcp_abort(pcb); return ERR_ABRT; }
    client=pcb; restart_input(); tcp_arg(pcb,NULL); tcp_recv(pcb,received); tcp_err(pcb,connection_error);
    return ERR_OK;
}
void print_app_header(void) {
    xil_printf("\r\nUWAC TCP server port %u: u32be sample count, int16le payload\r\n",SERVER_PORT);
}
int start_application(void) {
    struct tcp_pcb *listener;
    XAxiDma_Config *cfg;
#ifdef SDT
    cfg=XAxiDma_LookupConfig(DMA_BASE);
#else
    cfg=XAxiDma_LookupConfigBaseAddr(DMA_BASE);
#endif
    if (!cfg || XAxiDma_CfgInitialize(&dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(&dma)) {
        xil_printf("DMA initialization failed\r\n"); hw_fault=1; return -1;
    }
    XAxiDma_IntrDisable(&dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    Xil_Out32(GPIO_BASE+GPIO_TRI_OFFSET,0xFFFFFFFFU);
    listener=tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!listener) return -1;
    if (tcp_bind(listener,IP_ANY_TYPE,SERVER_PORT)!=ERR_OK) { tcp_close(listener); return -1; }
    listener=tcp_listen(listener);
    if (!listener) return -1;
    tcp_accept(listener,accepted);
    xil_printf("DMA max bytes %u; server listening on port %u\r\n",(unsigned int)dma.TxBdRing.MaxTransferLen,(unsigned int)SERVER_PORT);
    return 0;
}
int transfer_data(void) {
    uint32_t status, dma_status;
    if (!client) return 0;
    if (state==PREFILL) {
        if (received_bytes==payload_bytes && header_bytes==4) {
            status=Xil_In32(GPIO_BASE+GPIO_DATA_OFFSET);
            dma_status=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_TX_OFFSET+XAXIDMA_SR_OFFSET);
            xil_printf("Before DMA: GPIO=0x%08x DMA_SR=0x%08x\r\n",(unsigned int)status,(unsigned int)dma_status);
            if ((status & STATUS_BUSY) || (!(dma_status & XAXIDMA_HALTED_MASK) && !(dma_status & XAXIDMA_IDLE_MASK))) {
                xil_printf("Error: PL or DMA already busy\r\n"); hw_fault=1; send_result(2,1); return 0;
            }
            Xil_Out32(CTRL_BASE+4U,sample_count);
            Xil_DCacheFlushRange((UINTPTR)waveform,payload_bytes);
            { int rc=XAxiDma_SimpleTransfer(&dma,(UINTPTR)waveform,payload_bytes,XAXIDMA_DMA_TO_DEVICE);
              if (rc!=XST_SUCCESS) { xil_printf("Error: DMA submit rc=%d\r\n",rc); hw_fault=1; send_result(2,1); return 0; } }
            header_bytes=5; XTime_GetTime(&started);
            xil_printf("DMA started; delaying before PL start\r\n");
        }
        dma_status=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_TX_OFFSET+XAXIDMA_SR_OFFSET);
        if (dma_status & DMA_ERROR_MASK) { xil_printf("Error: DMA prefill SR=0x%08x\r\n",(unsigned int)dma_status); hw_fault=1; send_result(2,1); }
        else if (elapsed_ms()>=PREFILL_DELAY_MS) { Xil_Out32(CTRL_BASE,1U); XTime_GetTime(&started); state=WAIT_BUSY; }
    } else if (state==WAIT_BUSY || state==TRANSMIT) {
        status=Xil_In32(GPIO_BASE+GPIO_DATA_OFFSET);
        dma_status=XAxiDma_ReadReg(dma.RegBase,XAXIDMA_TX_OFFSET+XAXIDMA_SR_OFFSET);
        if ((dma_status & DMA_ERROR_MASK) || (status & (STATUS_UNDERFLOW|STATUS_ZERO_LEN))) {
            xil_printf("Error: PL transmit GPIO=0x%08x DMA_SR=0x%08x\r\n",(unsigned int)status,(unsigned int)dma_status);
            hw_fault=1; send_result((status & STATUS_UNDERFLOW)?3:2,1);
        } else if (state==WAIT_BUSY && (status & STATUS_BUSY)) {
            XTime_GetTime(&started); state=TRANSMIT;
        } else if (state==WAIT_BUSY && elapsed_ms()>ACCEPT_TIMEOUT_MS) {
            hw_fault=1; send_result(4,1);
        } else if (state==TRANSMIT && (status & STATUS_DONE) && !(status & STATUS_BUSY)) {
            if (XAxiDma_Busy(&dma,XAXIDMA_DMA_TO_DEVICE)) { xil_printf("Error: PL done but DMA still busy, SR=0x%08x\r\n",(unsigned int)dma_status); hw_fault=1; send_result(2,1); }
            else { XTime_GetTime(&started); state=FINAL_HOLD; }
        } else if (state==TRANSMIT && elapsed_ms() > (sample_count/1000U)+EXTRA_SEND_TIMEOUT_MS) {
            hw_fault=1; send_result(4,1);
        }
    } else if (state==FINAL_HOLD && elapsed_ms()>=FINAL_DAC_SETTLE_MS) send_result(0,0);
    if (state==RESPOND && tcp_sndbuf(client)>=1) {
        err_t e=tcp_write(client,&response,1,TCP_WRITE_FLAG_COPY);
        if (e==ERR_OK) {
            tcp_output(client);
            if (close_after_response) {
                struct tcp_pcb *c=client; client=NULL;
                tcp_arg(c,NULL); tcp_recv(c,NULL); tcp_err(c,NULL);
                if (tcp_close(c)!=ERR_OK) tcp_abort(c);
                state=hw_fault?LOCKED:WAIT_HEADER;
            } else restart_input();
        } else if (e!=ERR_MEM) { struct tcp_pcb *c=client; tcp_abort(c); }
    }
    return 0;
}
