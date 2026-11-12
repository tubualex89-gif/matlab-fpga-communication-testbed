
`timescale 1 ns / 1 ps

	module Test_bed_tx_ctr_slave_lite_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 7
	)
	(
		// Users to add ports here
        output reg         tx_start,
        
        // MATLAB 载荷采样点数
        output wire [31:0] tx_payload_samples,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);


    // This IP uses 32-bit AXI-Lite data and a byte-addressed register map:
    // 0x00 (write-only): bit 0 writes a one-clock start pulse.
    // 0x04 (read/write): number of 16-bit payload samples.
    // Other addresses read as zero and ignore writes; responses are OKAY.
    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_hold;
    reg [C_S_AXI_DATA_WIDTH-1:0] wdata_hold;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold;
    reg aw_pending, w_pending;
    reg bvalid_reg, rvalid_reg;
    reg [C_S_AXI_DATA_WIDTH-1:0] payload_len;
    reg [C_S_AXI_DATA_WIDTH-1:0] rdata_reg;
    integer byte_index;

    // A single outstanding write: either channel can arrive first. Once
    // accepted, its READY stays low until the write response is retired.
    assign S_AXI_AWREADY = S_AXI_ARESETN && !aw_pending && !bvalid_reg;
    assign S_AXI_WREADY  = S_AXI_ARESETN && !w_pending && !bvalid_reg;
    assign S_AXI_BVALID  = bvalid_reg;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_ARREADY = S_AXI_ARESETN && !rvalid_reg;
    assign S_AXI_RVALID  = rvalid_reg;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RDATA   = rdata_reg;
    assign tx_payload_samples = payload_len;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            awaddr_hold <= 0;
            wdata_hold <= 0;
            wstrb_hold <= 0;
            bvalid_reg <= 1'b0;
            payload_len <= 0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                awaddr_hold <= S_AXI_AWADDR;
                aw_pending <= 1'b1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wdata_hold <= S_AXI_WDATA;
                wstrb_hold <= S_AXI_WSTRB;
                w_pending <= 1'b1;
            end
            if (aw_pending && w_pending && !bvalid_reg) begin
                case (awaddr_hold)
                    'h00: if (wstrb_hold[0] && wdata_hold[0])
                        tx_start <= 1'b1;
                    'h04: begin
                        for (byte_index = 0; byte_index < C_S_AXI_DATA_WIDTH/8; byte_index = byte_index + 1) begin
                            if (wstrb_hold[byte_index])
                                payload_len[byte_index*8 +: 8] <= wdata_hold[byte_index*8 +: 8];
                        end
                    end
                    default: begin end
                endcase
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                bvalid_reg <= 1'b1;
            end else if (bvalid_reg && S_AXI_BREADY) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

    // Snapshot each read response and hold it stable until RREADY.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 0;
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                case (S_AXI_ARADDR)
                    'h04: rdata_reg <= payload_len;
                    default: rdata_reg <= 0;
                endcase
                rvalid_reg <= 1'b1;
            end else if (rvalid_reg && S_AXI_RREADY) begin
                rvalid_reg <= 1'b0;
            end
        end
    end
endmodule
