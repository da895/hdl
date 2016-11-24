// ***************************************************************************
// ***************************************************************************
// Copyright 2014(c) Analog Devices, Inc.
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//     - Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     - Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in
//       the documentation and/or other materials provided with the
//       distribution.
//     - Neither the name of Analog Devices, Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//     - The use of this software may or may not infringe the patent rights
//       of one or more patent holders.  This license does not release you
//       from the requirement that you obtain separate licenses from these
//       patent holders to use this software.
//     - Use of the software either in source or binary form, must be run
//       on or directly connected to an Analog Devices Inc. component.
//
// THIS SOFTWARE IS PROVIDED BY ANALOG DEVICES "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
// INCLUDING, BUT NOT LIMITED TO, NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED.
//
// IN NO EVENT SHALL ANALOG DEVICES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, INTELLECTUAL PROPERTY
// RIGHTS, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ***************************************************************************
// IP used to monitor interrupt handling latency for a system.
// Control register, bit 0 enables the core. If it's set to 0, the interrupt
// won't be activated and all counters will be reset to 0
// ***************************************************************************

`timescale 1ns/100ps

module axi_intr_monitor
(
  output          irq,

// axi interface

  input           s_axi_aclk,
  input           s_axi_aresetn,
  input           s_axi_awvalid,
  input   [31:0]  s_axi_awaddr,
  output          s_axi_awready,
  input           s_axi_wvalid,
  input   [31:0]  s_axi_wdata,
  input   [3:0]   s_axi_wstrb,
  output          s_axi_wready,
  output          s_axi_bvalid,
  output  [1:0]   s_axi_bresp,
  input           s_axi_bready,
  input           s_axi_arvalid,
  input   [31:0]  s_axi_araddr,
  output          s_axi_arready,
  output          s_axi_rvalid,
  output  [1:0]   s_axi_rresp,
  output  [31:0]  s_axi_rdata,
  input           s_axi_rready,
  input   [ 2:0]  s_axi_awprot,
  input   [ 2:0]  s_axi_arprot

);

parameter VERSION = 32'h00010000;

//------------------------------------------------------------------------------
//----------- Registers Declarations -------------------------------------------
//------------------------------------------------------------------------------

reg     [31:0]  up_rdata                    = 'd0;
reg             up_wack                     = 'd0;
reg             up_rack                     = 'd0;
reg             pwm_gen_clk                 = 'd0;
reg     [31:0]  scratch                     = 'd0;
reg     [31:0]  control                     = 'd0;
reg             interrupt                   = 'd0;
reg     [31:0]  counter_to_interrupt        = 'd0;
reg     [31:0]  counter_to_interrupt_cnt    = 'd0;
reg     [31:0]  counter_from_interrupt      = 'd0;
reg     [31:0]  counter_interrupt_handling  = 'd0;
reg     [31:0]  min_interrupt_handling      = 'd0;
reg     [31:0]  max_interrupt_handling      = 'd0;
reg             interrupt_d1                = 'd0;

//------------------------------------------------------------------------------
//----------- Wires Declarations -----------------------------------------------
//------------------------------------------------------------------------------

wire            up_rreq_s;
wire            up_wreq_s;
wire    [13:0]  up_raddr_s;
wire    [13:0]  up_waddr_s;
wire    [31:0]  up_wdata_s;

//------------------------------------------------------------------------------
//----------- Assign/Always Blocks ---------------------------------------------
//------------------------------------------------------------------------------

assign irq = interrupt & control[0];

always @(negedge s_axi_aresetn or posedge s_axi_aclk) begin
  if (s_axi_aresetn == 1'b0 || control[0] == 1'b0) begin
    counter_to_interrupt_cnt <= 0;
    counter_interrupt_handling <= 'd0;
    counter_from_interrupt <= 32'h0;
    min_interrupt_handling <= 'd0;
    max_interrupt_handling <= 'd0;
    interrupt_d1 <= 0;
  end else begin
    interrupt_d1 <= irq;
    if (irq == 1'b1) begin
      counter_to_interrupt_cnt <= counter_to_interrupt;
    end else if (counter_to_interrupt_cnt > 0) begin
      counter_to_interrupt_cnt <= counter_to_interrupt_cnt - 1;
    end
    if (irq == 1'b0 && interrupt_d1 == 1'b1) begin
      counter_from_interrupt <= 32'h0;
      counter_interrupt_handling <= counter_from_interrupt;
      if (min_interrupt_handling > counter_from_interrupt) begin
        min_interrupt_handling <= counter_from_interrupt;
      end
      if (max_interrupt_handling < counter_from_interrupt) begin
        max_interrupt_handling <= counter_from_interrupt;
      end
    end else begin
      counter_from_interrupt <= counter_from_interrupt + 1;
    end
  end
end

always @(negedge s_axi_aresetn or posedge s_axi_aclk) begin
  if (s_axi_aresetn == 0) begin
    up_wack                    <= 1'b0;
    scratch                    <= 'd0;
    control                    <= 'd0;
    interrupt                  <= 'd0;
    counter_to_interrupt       <= 'd0;
  end else begin
    up_wack  <= up_wreq_s;
    if ((up_wreq_s == 1'b1) && (up_waddr_s[3:0] == 4'h1)) begin
      scratch <= up_wdata_s;
    end
    if ((up_wreq_s == 1'b1) && (up_waddr_s[3:0] == 4'h2)) begin
      control <= up_wdata_s;
    end
    if ((up_wreq_s == 1'b1) && (up_waddr_s[3:0] == 4'h3)) begin
      interrupt <= interrupt & ~up_wdata_s[0];
    end else begin
      if (counter_to_interrupt_cnt == 32'h0 && control[0] == 1'b1) begin
        interrupt <= 1'b1;
      end
    end
    if ((up_wreq_s == 1'b1) && (up_waddr_s[3:0] == 4'h4)) begin
      counter_to_interrupt <= up_wdata_s;
    end
  end
end

always @(negedge s_axi_aresetn or posedge s_axi_aclk) begin
  if (s_axi_aresetn == 0) begin
    up_rack <= 'd0;
    up_rdata <= 'd0;
  end else begin
    up_rack <= up_rreq_s;
    if (up_rreq_s == 1'b1) begin
      case (up_raddr_s[3:0])
        4'h0: up_rdata <= VERSION;
        4'h1: up_rdata <= scratch;
        4'h2: up_rdata <= control;
        4'h3: up_rdata <= {31'h0,interrupt};
        4'h4: up_rdata <= counter_to_interrupt;
        4'h5: up_rdata <= counter_from_interrupt;
        4'h6: up_rdata <= counter_interrupt_handling;
        4'h7: up_rdata <= min_interrupt_handling;
        4'h8: up_rdata <= max_interrupt_handling;
        default: up_rdata <= 0;
      endcase
    end else begin
      up_rdata <= 32'd0;
    end
  end
end

// up bus interface

up_axi i_up_axi(
  .up_rstn(s_axi_aresetn),
  .up_clk(s_axi_aclk),
  .up_axi_awvalid(s_axi_awvalid),
  .up_axi_awaddr(s_axi_awaddr),
  .up_axi_awready(s_axi_awready),
  .up_axi_wvalid(s_axi_wvalid),
  .up_axi_wdata(s_axi_wdata),
  .up_axi_wstrb(s_axi_wstrb),
  .up_axi_wready(s_axi_wready),
  .up_axi_bvalid(s_axi_bvalid),
  .up_axi_bresp(s_axi_bresp),
  .up_axi_bready(s_axi_bready),
  .up_axi_arvalid(s_axi_arvalid),
  .up_axi_araddr(s_axi_araddr),
  .up_axi_arready(s_axi_arready),
  .up_axi_rvalid(s_axi_rvalid),
  .up_axi_rresp(s_axi_rresp),
  .up_axi_rdata(s_axi_rdata),
  .up_axi_rready(s_axi_rready),
  .up_wreq (up_wreq_s),
  .up_waddr (up_waddr_s),
  .up_wdata (up_wdata_s),
  .up_wack (up_wack),
  .up_rreq (up_rreq_s),
  .up_raddr (up_raddr_s),
  .up_rdata (up_rdata),
  .up_rack (up_rack));

endmodule

// ***************************************************************************
// ***************************************************************************
