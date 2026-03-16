// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Tim Fischer <fischeti@iis.ee.ethz.ch>

module picobello_top
  import picobello_pkg::*;
  import cheshire_pkg::*;
  import floo_pkg::*;
  import snitch_cluster_pkg::*;
  import floo_picobello_noc_pkg::*;
(
  input  logic                                                             clk_i,
  input  logic                                                             rst_ni,
  input  logic                                                             test_mode_i,
  input  logic         [                           1:0]                    boot_mode_i,
  input  logic                                                             rtc_i,
  input  logic                                                             clk_rst_bypass_i,
  // JTAG
  input  logic                                                             jtag_tck_i,
  input  logic                                                             jtag_trst_ni,
  input  logic                                                             jtag_tms_i,
  input  logic                                                             jtag_tdi_i,
  output logic                                                             jtag_tdo_o,
  output logic                                                             jtag_tdo_oe_o,
  // UART interface
  output logic                                                             uart_tx_o,
  input  logic                                                             uart_rx_i,
  // UART modem flow control
  output logic                                                             uart_rts_no,
  output logic                                                             uart_dtr_no,
  input  logic                                                             uart_cts_ni,
  input  logic                                                             uart_dsr_ni,
  input  logic                                                             uart_dcd_ni,
  input  logic                                                             uart_rin_ni,
  // I2C interface
  output logic                                                             i2c_sda_o,
  input  logic                                                             i2c_sda_i,
  output logic                                                             i2c_sda_en_o,
  output logic                                                             i2c_scl_o,
  input  logic                                                             i2c_scl_i,
  output logic                                                             i2c_scl_en_o,
  // SPI host interface
  output logic                                                             spih_sck_o,
  output logic                                                             spih_sck_en_o,
  output logic         [                 SpihNumCs-1:0]                    spih_csb_o,
  output logic         [                 SpihNumCs-1:0]                    spih_csb_en_o,
  output logic         [                           3:0]                    spih_sd_o,
  output logic         [                           3:0]                    spih_sd_en_o,
  input  logic         [                           3:0]                    spih_sd_i,
  // GPIO interface
  input  logic         [                          31:0]                    gpio_i,
  output logic         [                          31:0]                    gpio_o,
  output logic         [                          31:0]                    gpio_en_o,
  // Chip-level register interface
  output csh_reg_req_t [CshRegExtChipCtrl:CshRegExtFLL]                    reg_req_o,
  input  csh_reg_rsp_t [CshRegExtChipCtrl:CshRegExtFLL]                    reg_rsp_i,
  // Serial link interface
  input  logic         [              SlinkNumChan-1:0]                    slink_rcv_clk_i,
  output logic         [              SlinkNumChan-1:0]                    slink_rcv_clk_o,
  input  logic         [              SlinkNumChan-1:0][SlinkNumLanes-1:0] slink_i,
  output logic         [              SlinkNumChan-1:0][SlinkNumLanes-1:0] slink_o,
  // DRAM Serial link interface
  input  logic         [              SlinkNumChan-1:0]                    dram_slink_rcv_clk_i,
  output logic         [              SlinkNumChan-1:0]                    dram_slink_rcv_clk_o,
  input  logic         [              SlinkNumChan-1:0][SlinkNumLanes-1:0] dram_slink_i,
  output logic         [              SlinkNumChan-1:0][SlinkNumLanes-1:0] dram_slink_o
);

  floo_req_t [MeshDim.x-1:0][MeshDim.y-1:0][West:North] floo_req_inA, floo_req_inB, floo_req_inC, floo_req_outA, floo_req_outB, floo_req_outC;
  floo_rsp_t [MeshDim.x-1:0][MeshDim.y-1:0][West:North] floo_rsp_inA, floo_rsp_inB, floo_rsp_inC, floo_rsp_outA, floo_rsp_outB, floo_rsp_outC;
  floo_wide_t [MeshDim.x-1:0][MeshDim.y-1:0][West:North] floo_wide_inA, floo_wide_inB, floo_wide_inC, floo_wide_outA, floo_wide_outB, floo_wide_outC;

  logic [NumClusters-1:0] cluster_clk_en, cluster_rst_n;
  logic [NumMemTiles-1:0] mem_tile_clk_en, mem_tile_rst_n;
  logic fhg_spu_clk_en, fhg_spu_rst_n;

  ///////////////////
  // Cluster tiles //
  ///////////////////

  logic [NumClusters-1:0][NrCores-1:0] debug_req, meip, mtip, msip;

  // TODO: Connect the debug and interrupt signals
  assign debug_req = '0;
  assign meip      = '0;
  assign mtip      = '0;
  assign msip      = '0;

  for (genvar c = 0; c < NumClusters; c++) begin : gen_clusters

    localparam int ClusterSamIdx = c + ClusterX0Y0SamIdx;
    localparam id_t ClusterId = Sam[ClusterSamIdx].idx;
    localparam id_t ClusterPhysicalId = picobello_pkg::SamPhysical[ClusterSamIdx].idx;
    localparam int X = int'(ClusterPhysicalId.x);
    localparam int Y = int'(ClusterPhysicalId.y);
    localparam int unsigned HartBaseId = c * NrCores + 1;  // Cheshire is hart 0
    localparam axi_wide_in_addr_t ClusterBaseAddr = Sam[ClusterSamIdx].start_addr;

    cluster_tileTMR i_cluster_tile (
      .clk_i,
      .rst_ni,
      .test_enable_i      (test_mode_i),
      .tile_clk_en_i      (cluster_clk_en[c]),
      .tile_rst_ni        (cluster_rst_n[c]),
      .clk_rst_bypass_i   (clk_rst_bypass_i),
      .debug_req_i        (debug_req[c]),
      .meip_i             (meip[c]),
      .mtip_i             (mtip[c]),
      .msip_i             (msip[c]),
      .hart_base_id_i     (HartBaseId[9:0]),
      .cluster_base_addr_i(ClusterBaseAddr),
      .id_i               (ClusterId),
      .floo_req_oA         (floo_req_outA[X][Y]),
      .floo_req_oB         (floo_req_outB[X][Y]),
      .floo_req_oC         (floo_req_outC[X][Y]),
      .floo_rsp_iA         (floo_rsp_inA[X][Y]),
      .floo_rsp_iB         (floo_rsp_inB[X][Y]),
      .floo_rsp_iC         (floo_rsp_inC[X][Y]),
      .floo_wide_oA        (floo_wide_outA[X][Y]),
      .floo_wide_oB        (floo_wide_outB[X][Y]),
      .floo_wide_oC        (floo_wide_outC[X][Y]),
      .floo_req_iA         (floo_req_inA[X][Y]),
      .floo_req_iB         (floo_req_inB[X][Y]),
      .floo_req_iC         (floo_req_inC[X][Y]),
      .floo_rsp_oA         (floo_rsp_outA[X][Y]),
      .floo_rsp_oB         (floo_rsp_outB[X][Y]),
      .floo_rsp_oC         (floo_rsp_outC[X][Y]),
      .floo_wide_iA        (floo_wide_inA[X][Y]),
      .floo_wide_iB        (floo_wide_inB[X][Y]),
      .floo_wide_iC        (floo_wide_inC[X][Y])
    );
  end

  ///////////////////
  // Cheshire tile //
  ///////////////////

  // TODO(fischeti): Connect the interrupt signals
  logic [iomsb(NumIrqCtxts*CheshireCfg.NumExtIrqHarts):0] xeip_ext;
  logic [            iomsb(CheshireCfg.NumExtIrqHarts):0] mtip_ext;
  logic [            iomsb(CheshireCfg.NumExtIrqHarts):0] msip_ext;

  localparam id_t CheshireId = Sam[CheshireInternalSamIdx].idx;
  localparam id_t CheshirePhysicalId = SamPhysical[CheshireInternalSamIdx].idx;

  cheshire_tileTMR i_cheshire_tile (
    .clk_i,
    .rst_ni,
    .test_mode_i,
    .boot_mode_i,
    .rtc_i,
    .xeip_ext_o       (xeip_ext),
    .mtip_ext_o       (mtip_ext),
    .msip_ext_o       (msip_ext),
    .jtag_tck_i,
    .jtag_trst_ni,
    .jtag_tms_i,
    .jtag_tdi_i,
    .jtag_tdo_o,
    .jtag_tdo_oe_o,
    .uart_tx_o,
    .uart_rx_i,
    .uart_rts_no,
    .uart_dtr_no,
    .uart_cts_ni,
    .uart_dsr_ni,
    .uart_dcd_ni,
    .uart_rin_ni,
    .i2c_sda_o,
    .i2c_sda_i,
    .i2c_sda_en_o,
    .i2c_scl_o,
    .i2c_scl_i,
    .i2c_scl_en_o,
    .spih_sck_o,
    .spih_sck_en_o,
    .spih_csb_o,
    .spih_csb_en_o,
    .spih_sd_o,
    .spih_sd_en_o,
    .spih_sd_i,
    .gpio_i,
    .gpio_o,
    .gpio_en_o,
    .reg_req_o,
    .reg_rsp_i,
    .slink_rcv_clk_i,
    .slink_rcv_clk_o,
    .slink_i,
    .slink_o,
    .dram_slink_rcv_clk_i,
    .dram_slink_rcv_clk_o,
    .dram_slink_i,
    .dram_slink_o,
    .id_i             (CheshireId),
    .cluster_clk_en_o (cluster_clk_en),
    .cluster_rst_no   (cluster_rst_n),
    .mem_tile_clk_en_o(mem_tile_clk_en),
    .mem_tile_rst_no  (mem_tile_rst_n),
    .fhg_spu_clk_en_o (fhg_spu_clk_en),
    .fhg_spu_rst_no   (fhg_spu_rst_n),
    .floo_req_west_oA  (floo_req_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_west_oB  (floo_req_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_west_oC  (floo_req_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_iA  (floo_rsp_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_iB  (floo_rsp_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_iC  (floo_rsp_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_oA (floo_wide_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_oB (floo_wide_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_oC (floo_wide_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_west_iA  (floo_req_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_west_iB  (floo_req_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_west_iC  (floo_req_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_oA  (floo_rsp_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_oB  (floo_rsp_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_rsp_west_oC  (floo_rsp_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_iA (floo_wide_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_iB (floo_wide_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_wide_west_iC (floo_wide_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][West]),
    .floo_req_south_oA (floo_req_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_req_south_oB (floo_req_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_req_south_oC (floo_req_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_iA (floo_rsp_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_iB (floo_rsp_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_iC (floo_rsp_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_oA (floo_wide_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_oB (floo_wide_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_oC (floo_wide_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_req_south_iA (floo_req_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_req_south_iB (floo_req_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_req_south_iC (floo_req_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_oA (floo_rsp_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_oB (floo_rsp_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_rsp_south_oC (floo_rsp_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_iA (floo_wide_inA[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_iB (floo_wide_inB[CheshirePhysicalId.x][CheshirePhysicalId.y][South]),
    .floo_wide_south_iC (floo_wide_inC[CheshirePhysicalId.x][CheshirePhysicalId.y][South])
  );
  assign floo_req_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_req_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_req_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_rsp_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_rsp_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_rsp_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][North]  = '0;
  assign floo_wide_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][North] = '0;
  assign floo_wide_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][North] = '0;
  assign floo_wide_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][North] = '0;
  assign floo_req_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_req_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_req_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_rsp_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_rsp_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_rsp_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][East]   = '0;
  assign floo_wide_outA[CheshirePhysicalId.x][CheshirePhysicalId.y][East]  = '0;
  assign floo_wide_outB[CheshirePhysicalId.x][CheshirePhysicalId.y][East]  = '0;
  assign floo_wide_outC[CheshirePhysicalId.x][CheshirePhysicalId.y][East]  = '0;

  //////////////////
  // FhG SPU tile //
  //////////////////

  // TODO: Connect the debug and interrupt signals
  logic [8:0] fhg_spu_debug_req, fhg_spu_meip, fhg_spu_mtip, fhg_spu_msip;

  assign fhg_spu_debug_req = '0;
  assign fhg_spu_meip      = '0;
  assign fhg_spu_mtip      = '0;
  assign fhg_spu_msip      = '0;

  localparam id_t FhgSpuId = Sam[FhgSpuSamIdx].idx;

  // Add offset to consider Cheshire as hart 0
  localparam int unsigned FhgSpuHartBaseId = NumClusters * NrCores + 1;
  localparam id_t FhgSpuPhysicalId = SamPhysical[FhgSpuSamIdx].idx;

  fhg_spu_tileTMR i_fhg_spu_tile (
    .clk_i,
    .rst_ni,
    .test_enable_i      (test_mode_i),
    .tile_clk_en_i      (fhg_spu_clk_en),
    .tile_rst_ni        (fhg_spu_rst_n),
    .clk_rst_bypass_i   (clk_rst_bypass_i),
    .debug_req_i        (fhg_spu_debug_req),
    .meip_i             (fhg_spu_meip),
    .mtip_i             (fhg_spu_mtip),
    .msip_i             (fhg_spu_msip),
    .hart_base_id_i     (FhgSpuHartBaseId[9:0]),
    .cluster_base_addr_i(Sam[FhgSpuSamIdx].start_addr),
    .id_i               (FhgSpuId),
    .floo_req_west_oA    (floo_req_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_west_oB    (floo_req_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_west_oC    (floo_req_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_iA    (floo_rsp_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_iB    (floo_rsp_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_iC    (floo_rsp_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_oA   (floo_wide_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_oB   (floo_wide_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_oC   (floo_wide_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_west_iA    (floo_req_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_west_iB    (floo_req_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_west_iC    (floo_req_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_oA    (floo_rsp_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_oB    (floo_rsp_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_rsp_west_oC    (floo_rsp_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_iA   (floo_wide_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_iB   (floo_wide_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_wide_west_iC   (floo_wide_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][West]),
    .floo_req_north_oA   (floo_req_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_req_north_oB   (floo_req_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_req_north_oC   (floo_req_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_iA   (floo_rsp_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_iB   (floo_rsp_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_iC   (floo_rsp_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_oA  (floo_wide_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_oB  (floo_wide_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_oC  (floo_wide_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_req_north_iA   (floo_req_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_req_north_iB   (floo_req_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_req_north_iC   (floo_req_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_oA   (floo_rsp_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_oB   (floo_rsp_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_rsp_north_oC   (floo_rsp_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_iA  (floo_wide_inA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_iB  (floo_wide_inB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North]),
    .floo_wide_north_iC  (floo_wide_inC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][North])
  );
  assign floo_req_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_req_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_req_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_rsp_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_rsp_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_rsp_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]   = '0;
  assign floo_wide_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]  = '0;
  assign floo_wide_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]  = '0;
  assign floo_wide_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][East]  = '0;
  assign floo_req_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_req_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_req_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_rsp_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_rsp_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_rsp_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South]  = '0;
  assign floo_wide_outA[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South] = '0;
  assign floo_wide_outB[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South] = '0;
  assign floo_wide_outC[FhgSpuPhysicalId.x][FhgSpuPhysicalId.y][South] = '0;

  //////////////
  // Mem tile //
  //////////////

  for (genvar m = 0; m < NumMemTiles; m++) begin : gen_memtile

    localparam int MemTileSamIdx = m + L2Spm0SamIdx;
    localparam id_t MemTileId = Sam[MemTileSamIdx].idx;
    localparam id_t MemTilePhysicalId = SamPhysical[MemTileSamIdx].idx;
    localparam int MemTileX = int'(MemTilePhysicalId.x);
    localparam int MemTileY = int'(MemTilePhysicalId.y);

    mem_tileTMR #(
`ifndef TARGET_SYNTHESIS
      .MemTileId(int'(m))
`endif
    ) i_mem_tile (
      .clk_i,
      .rst_ni,
      .test_enable_i   (test_mode_i),
      .tile_clk_en_i   (mem_tile_clk_en[m]),
      .tile_rst_ni     (mem_tile_rst_n[m]),
      .clk_rst_bypass_i(clk_rst_bypass_i),
      .id_i            (MemTileId),
      .floo_req_oA     (floo_req_outA[MemTileX][MemTileY]),
      .floo_req_oB     (floo_req_outB[MemTileX][MemTileY]),
      .floo_req_oC     (floo_req_outC[MemTileX][MemTileY]),
      .floo_rsp_iA     (floo_rsp_inA[MemTileX][MemTileY]),
      .floo_rsp_iB     (floo_rsp_inB[MemTileX][MemTileY]),
      .floo_rsp_iC     (floo_rsp_inC[MemTileX][MemTileY]),
      .floo_wide_oA    (floo_wide_outA[MemTileX][MemTileY]),
      .floo_wide_oB    (floo_wide_outB[MemTileX][MemTileY]),
      .floo_wide_oC    (floo_wide_outC[MemTileX][MemTileY]),
      .floo_req_iA     (floo_req_inA[MemTileX][MemTileY]),
      .floo_req_iB     (floo_req_inB[MemTileX][MemTileY]),
      .floo_req_iC     (floo_req_inC[MemTileX][MemTileY]),
      .floo_rsp_oA     (floo_rsp_outA[MemTileX][MemTileY]),
      .floo_rsp_oB     (floo_rsp_outB[MemTileX][MemTileY]),
      .floo_rsp_oC     (floo_rsp_outC[MemTileX][MemTileY]),
      .floo_wide_iA    (floo_wide_inA[MemTileX][MemTileY]),
      .floo_wide_iB    (floo_wide_inB[MemTileX][MemTileY]),
      .floo_wide_iC    (floo_wide_inC[MemTileX][MemTileY])
    );

  end

  ///////////////
  // SPM  tile //
  ///////////////

  // Narrow SPM tile
  localparam int SpmNarrowTileSamIdx = int'(TopSpmNarrowSamIdx);
  localparam id_t SpmNarrowTileId = Sam[SpmNarrowTileSamIdx].idx;
  localparam id_t SpmNarrowTilePhysicalId = SamPhysical[SpmNarrowTileSamIdx].idx;
  localparam int SpmNarrowTileX = int'(SpmNarrowTilePhysicalId.x);
  localparam int SpmNarrowTileY = int'(SpmNarrowTilePhysicalId.y);

  spm_tileTMR #(
    .axi_aw_chan_t     (floo_picobello_noc_pkg::axi_narrow_out_aw_chan_t),
    .axi_w_chan_t      (floo_picobello_noc_pkg::axi_narrow_out_w_chan_t),
    .axi_b_chan_t      (floo_picobello_noc_pkg::axi_narrow_out_b_chan_t),
    .axi_ar_chan_t     (floo_picobello_noc_pkg::axi_narrow_out_ar_chan_t),
    .axi_r_chan_t      (floo_picobello_noc_pkg::axi_narrow_out_r_chan_t),
    .axi_to_mem_req_t  (floo_picobello_noc_pkg::axi_narrow_out_req_t),
    .axi_to_mem_rsp_t  (floo_picobello_noc_pkg::axi_narrow_out_rsp_t),
    .AxiIdWidth        (AxiCfgN.InIdWidth),
    .AxiDataWidth      (AxiCfgN.DataWidth),
    .SpmTileSize       (SpmNarrowTileSize),
    .SpmWordsPerBank   (SpmNarrowWordsPerBank),
    .SpmDataWidth      (SpmNarrowDataWidth),
    .SpmNumBanksPerWord(SpmNarrowNumBanksPerWord),
    .SpmNumBankRows    (SpmNarrowNumBankRows),
    .IsNarrow          (1'b1)
  ) i_narrow_spm_tile (
    .clk_i,
    .rst_ni,
    .test_enable_i(test_mode_i),
    .id_i         (SpmNarrowTileId),
    .floo_req_oA  (floo_req_outA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_req_oB  (floo_req_outB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_req_oC  (floo_req_outC[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_iA  (floo_rsp_inA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_iB  (floo_rsp_inB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_iC  (floo_rsp_inC[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_oA (floo_wide_outA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_oB (floo_wide_outB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_oC (floo_wide_outC[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_req_iA  (floo_req_inA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_req_iB  (floo_req_inB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_req_iC  (floo_req_inC[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_oA  (floo_rsp_outA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_oB  (floo_rsp_outB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_rsp_oC  (floo_rsp_outC[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_iA (floo_wide_inA[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_iB (floo_wide_inB[SpmNarrowTileX][SpmNarrowTileY]),
    .floo_wide_iC (floo_wide_inC[SpmNarrowTileX][SpmNarrowTileY])
  );

  // Wide SPM tile
  localparam int SpmWideTileSamIdx = int'(TopSpmWideSamIdx);
  localparam id_t SpmWideTileId = Sam[SpmWideTileSamIdx].idx;
  localparam id_t SpmWideTilePhysicalId = SamPhysical[SpmWideTileSamIdx].idx;
  localparam int SpmWideTileX = int'(SpmWideTilePhysicalId.x);
  localparam int SpmWideTileY = int'(SpmWideTilePhysicalId.y);

  spm_tileTMR #(
    .axi_aw_chan_t     (floo_picobello_noc_pkg::axi_wide_out_aw_chan_t),
    .axi_w_chan_t      (floo_picobello_noc_pkg::axi_wide_out_w_chan_t),
    .axi_b_chan_t      (floo_picobello_noc_pkg::axi_wide_out_b_chan_t),
    .axi_ar_chan_t     (floo_picobello_noc_pkg::axi_wide_out_ar_chan_t),
    .axi_r_chan_t      (floo_picobello_noc_pkg::axi_wide_out_r_chan_t),
    .axi_to_mem_req_t  (floo_picobello_noc_pkg::axi_wide_out_req_t),
    .axi_to_mem_rsp_t  (floo_picobello_noc_pkg::axi_wide_out_rsp_t),
    .AxiIdWidth        (AxiCfgW.InIdWidth),
    .AxiDataWidth      (AxiCfgW.DataWidth),
    .SpmTileSize       (SpmWideTileSize),
    .SpmWordsPerBank   (SpmWideWordsPerBank),
    .SpmDataWidth      (SpmWideDataWidth),
    .SpmNumBanksPerWord(SpmWideNumBanksPerWord),
    .SpmNumBankRows    (SpmWideNumBankRows),
    .IsNarrow          (1'b0)
  ) i_wide_spm_tile (
    .clk_i,
    .rst_ni,
    .test_enable_i(test_mode_i),
    .id_i         (SpmWideTileId),
    .floo_req_oA  (floo_req_outA[SpmWideTileX][SpmWideTileY]),
    .floo_req_oB  (floo_req_outB[SpmWideTileX][SpmWideTileY]),
    .floo_req_oC  (floo_req_outC[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_iA  (floo_rsp_inA[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_iB  (floo_rsp_inB[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_iC  (floo_rsp_inC[SpmWideTileX][SpmWideTileY]),
    .floo_wide_oA (floo_wide_outA[SpmWideTileX][SpmWideTileY]),
    .floo_wide_oB (floo_wide_outB[SpmWideTileX][SpmWideTileY]),
    .floo_wide_oC (floo_wide_outC[SpmWideTileX][SpmWideTileY]),
    .floo_req_iA  (floo_req_inA[SpmWideTileX][SpmWideTileY]),
    .floo_req_iB  (floo_req_inB[SpmWideTileX][SpmWideTileY]),
    .floo_req_iC  (floo_req_inC[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_oA  (floo_rsp_outA[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_oB  (floo_rsp_outB[SpmWideTileX][SpmWideTileY]),
    .floo_rsp_oC  (floo_rsp_outC[SpmWideTileX][SpmWideTileY]),
    .floo_wide_iA (floo_wide_inA[SpmWideTileX][SpmWideTileY]),
    .floo_wide_iB (floo_wide_inB[SpmWideTileX][SpmWideTileY]),
    .floo_wide_iC (floo_wide_inC[SpmWideTileX][SpmWideTileY])
  );

  ////////////////
  // Dummy tile //
  ////////////////

  for (genvar d = 0; d < NumDummyTiles; d++) begin : gen_dummytiles

    localparam id_t DummyTileId = DummyIdx[d];
    localparam int DummyTileX = int'(DummyPhysicalIdx[d].x);
    localparam int DummyTileY = int'(DummyPhysicalIdx[d].y);

    dummy_tileTMR i_dummy_tile (
      .clk_i,
      .rst_ni,
      .test_enable_i(test_mode_i),
      .id_i         (DummyTileId),
      .floo_req_oA  (floo_req_outA[DummyTileX][DummyTileY]),
      .floo_req_oB  (floo_req_outB[DummyTileX][DummyTileY]),
      .floo_req_oC  (floo_req_outC[DummyTileX][DummyTileY]),
      .floo_rsp_iA  (floo_rsp_inA[DummyTileX][DummyTileY]),
      .floo_rsp_iB  (floo_rsp_inB[DummyTileX][DummyTileY]),
      .floo_rsp_iC  (floo_rsp_inC[DummyTileX][DummyTileY]),
      .floo_wide_oA (floo_wide_outA[DummyTileX][DummyTileY]),
      .floo_wide_oB (floo_wide_outB[DummyTileX][DummyTileY]),
      .floo_wide_oC (floo_wide_outC[DummyTileX][DummyTileY]),
      .floo_req_iA  (floo_req_inA[DummyTileX][DummyTileY]),
      .floo_req_iB  (floo_req_inB[DummyTileX][DummyTileY]),
      .floo_req_iC  (floo_req_inC[DummyTileX][DummyTileY]),
      .floo_rsp_oA  (floo_rsp_outA[DummyTileX][DummyTileY]),
      .floo_rsp_oB  (floo_rsp_outB[DummyTileX][DummyTileY]),
      .floo_rsp_oC  (floo_rsp_outC[DummyTileX][DummyTileY]),
      .floo_wide_iA (floo_wide_inA[DummyTileX][DummyTileY]),
      .floo_wide_iB (floo_wide_inB[DummyTileX][DummyTileY]),
      .floo_wide_iC (floo_wide_inC[DummyTileX][DummyTileY])
    );
  end

  /////////////////////
  // NoC Connections //
  /////////////////////

  for (genvar x = 0; x < MeshDim.x; x++) begin : gen_x
    for (genvar y = 0; y < MeshDim.y; y++) begin : gen_y
      for (genvar d = int'(North); d <= int'(West); d++) begin : gen_dir
        localparam route_direction_e Dir = route_direction_e'(d);
        if (is_tie_off(x, y, Dir)) begin : gen_tie_off
          assign floo_req_inA[x][y][Dir]  = '0;
          assign floo_req_inB[x][y][Dir]  = '0;
          assign floo_req_inC[x][y][Dir]  = '0;
          assign floo_rsp_inA[x][y][Dir]  = '0;
          assign floo_rsp_inB[x][y][Dir]  = '0;
          assign floo_rsp_inC[x][y][Dir]  = '0;
          assign floo_wide_inA[x][y][Dir] = '0;
          assign floo_wide_inB[x][y][Dir] = '0;
          assign floo_wide_inC[x][y][Dir] = '0;
        end else begin : gen_con
          localparam int Xn = neighbor_x(x, Dir);
          localparam int Yn = neighbor_y(y, Dir);
          localparam route_direction_e Dirn = opposite_dir(Dir);
          assign floo_req_inA[x][y][Dir]  = floo_req_outA[Xn][Yn][Dirn];
          assign floo_req_inB[x][y][Dir]  = floo_req_outB[Xn][Yn][Dirn];
          assign floo_req_inC[x][y][Dir]  = floo_req_outC[Xn][Yn][Dirn];
          assign floo_rsp_inA[x][y][Dir]  = floo_rsp_outA[Xn][Yn][Dirn];
          assign floo_rsp_inB[x][y][Dir]  = floo_rsp_outB[Xn][Yn][Dirn];
          assign floo_rsp_inC[x][y][Dir]  = floo_rsp_outC[Xn][Yn][Dirn];
          assign floo_wide_inA[x][y][Dir] = floo_wide_outA[Xn][Yn][Dirn];
          assign floo_wide_inB[x][y][Dir] = floo_wide_outB[Xn][Yn][Dirn];
          assign floo_wide_inC[x][y][Dir] = floo_wide_outC[Xn][Yn][Dirn];
        end
      end
    end
  end

endmodule
