// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Tim Fischer <fischeti@iis.ee.ethz.ch>

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "tcdm_interface/typedef.svh"

module cluster_tileTMR
  import floo_pkg::*;
  import floo_picobello_noc_pkg::*;
  import snitch_cluster_pkg::*;
  import picobello_pkg::*;
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  logic                                    test_enable_i,
  input  logic                                    tile_clk_en_i,
  input  logic                                    tile_rst_ni,
  input  logic                                    clk_rst_bypass_i,
  // Cluster ports
  input  logic                      [NrCores-1:0] debug_req_i,
  input  logic                      [NrCores-1:0] meip_i,
  input  logic                      [NrCores-1:0] mtip_i,
  input  logic                      [NrCores-1:0] msip_i,
  input  logic                      [        9:0] hart_base_id_i,
  input  snitch_cluster_pkg::addr_t               cluster_base_addr_i,
  // Chimney ports
  input  id_t                                     id_i,
  // Router ports
  output floo_req_t                 [ West:North] floo_req_oA,
  output floo_req_t                 [ West:North] floo_req_oB,
  output floo_req_t                 [ West:North] floo_req_oC,
  input  floo_rsp_t                 [ West:North] floo_rsp_iA,
  input  floo_rsp_t                 [ West:North] floo_rsp_iB,
  input  floo_rsp_t                 [ West:North] floo_rsp_iC,
  output floo_wide_t                [ West:North] floo_wide_oA,
  output floo_wide_t                [ West:North] floo_wide_oB,
  output floo_wide_t                [ West:North] floo_wide_oC,
  input  floo_req_t                 [ West:North] floo_req_iA,
  input  floo_req_t                 [ West:North] floo_req_iB,
  input  floo_req_t                 [ West:North] floo_req_iC,
  output floo_rsp_t                 [ West:North] floo_rsp_oA,
  output floo_rsp_t                 [ West:North] floo_rsp_oB,
  output floo_rsp_t                 [ West:North] floo_rsp_oC,
  input  floo_wide_t                [ West:North] floo_wide_iA,
  input  floo_wide_t                [ West:North] floo_wide_iB,
  input  floo_wide_t                [ West:North] floo_wide_iC
);

  // Tile-specific reset and clock signals
  logic                                 tile_clk;
  logic                                 tile_rst_n;

  ////////////////////
  // Snitch Cluster //
  ////////////////////

  snitch_cluster_pkg::narrow_in_req_t   cluster_narrow_in_req;
  snitch_cluster_pkg::narrow_in_resp_t  cluster_narrow_in_rsp;
  snitch_cluster_pkg::narrow_out_req_t  cluster_narrow_out_req;
  snitch_cluster_pkg::narrow_out_resp_t cluster_narrow_out_rsp;
  snitch_cluster_pkg::wide_out_req_t    cluster_wide_out_req;
  snitch_cluster_pkg::wide_out_resp_t   cluster_wide_out_rsp;
  snitch_cluster_pkg::wide_in_req_t     cluster_wide_in_req;
  snitch_cluster_pkg::wide_in_resp_t    cluster_wide_in_rsp;

  snitch_cluster_pkg::narrow_out_req_t  cluster_narrow_ext_req;
  snitch_cluster_pkg::narrow_out_resp_t cluster_narrow_ext_rsp;
  snitch_cluster_pkg::tcdm_dma_req_t    cluster_tcdm_ext_req_aligned;
  snitch_cluster_pkg::tcdm_dma_req_t    cluster_tcdm_ext_req_misaligned;
  snitch_cluster_pkg::tcdm_dma_rsp_t    cluster_tcdm_ext_rsp_aligned;
  snitch_cluster_pkg::tcdm_dma_rsp_t    cluster_tcdm_ext_rsp_misaligned;

  localparam int unsigned HWPECtrlAddrWidth = 32;
  localparam int unsigned HWPECtrlDataWidth = 32;
  typedef logic [HWPECtrlAddrWidth-1:0] addr_hwpe_ctrl_t;
  typedef logic [HWPECtrlDataWidth-1:0] data_hwpe_ctrl_t;
  typedef logic [3:0] strb_hwpe_ctrl_t;

  `AXI_TYPEDEF_ALL(cluster_narrow_out_dw_conv, snitch_cluster_pkg::addr_t,
                   snitch_cluster_pkg::narrow_out_id_t, data_hwpe_ctrl_t, strb_hwpe_ctrl_t,
                   snitch_cluster_pkg::user_t)

  cluster_narrow_out_dw_conv_req_t cluster_narrow_out_dw_conv_req, cluster_narrow_out_cut_req;
  cluster_narrow_out_dw_conv_resp_t cluster_narrow_out_dw_conv_rsp, cluster_narrow_out_cut_rsp;

  `TCDM_TYPEDEF_ALL(hwpectrl, addr_hwpe_ctrl_t, data_hwpe_ctrl_t, strb_hwpe_ctrl_t, logic)

  hwpectrl_req_t               hwpectrl_req;
  hwpectrl_rsp_t               hwpectrl_rsp;

  logic          [NrCores-1:0] mxip;

  snitch_cluster_wrapper i_cluster (
    .clk_i            (tile_clk),
    .rst_ni           (tile_rst_n),
    .debug_req_i,
    .meip_i,
    .mtip_i,
    .msip_i,
    .hart_base_id_i,
    .cluster_base_addr_i,
    .mxip_i           (mxip),
    .clk_d2_bypass_i  ('0),
    .sram_cfgs_i      ('0),
    .narrow_in_req_i  (cluster_narrow_in_req),
    .narrow_in_resp_o (cluster_narrow_in_rsp),
    .narrow_out_req_o (cluster_narrow_out_req),
    .narrow_out_resp_i(cluster_narrow_out_rsp),
    .wide_out_req_o   (cluster_wide_out_req),
    .wide_out_resp_i  (cluster_wide_out_rsp),
    .wide_in_req_i    (cluster_wide_in_req),
    .wide_in_resp_o   (cluster_wide_in_rsp),
    .narrow_ext_req_o (cluster_narrow_ext_req),
    .narrow_ext_resp_i(cluster_narrow_ext_rsp),
    .tcdm_ext_req_i   (cluster_tcdm_ext_req_aligned),
    .tcdm_ext_resp_o  (cluster_tcdm_ext_rsp_aligned)
  );

  if (UseHWPE) begin : gen_hwpe

    // Convert narrow AXI's 64 bit DW down to 32
    axi_dw_converter #(
      .AxiMaxReads        (1),
      .AxiSlvPortDataWidth(snitch_cluster_pkg::NarrowDataWidth),
      .AxiMstPortDataWidth(HWPECtrlDataWidth),
      .AxiAddrWidth       (snitch_cluster_pkg::AddrWidth),
      .AxiIdWidth         (snitch_cluster_pkg::NarrowIdWidthOut),
      .aw_chan_t          (snitch_cluster_pkg::narrow_out_aw_chan_t),
      .mst_w_chan_t       (cluster_narrow_out_dw_conv_w_chan_t),
      .slv_w_chan_t       (snitch_cluster_pkg::narrow_out_w_chan_t),
      .b_chan_t           (snitch_cluster_pkg::narrow_out_b_chan_t),
      .ar_chan_t          (snitch_cluster_pkg::narrow_out_ar_chan_t),
      .mst_r_chan_t       (cluster_narrow_out_dw_conv_r_chan_t),
      .slv_r_chan_t       (snitch_cluster_pkg::narrow_out_r_chan_t),
      .axi_mst_req_t      (cluster_narrow_out_dw_conv_req_t),
      .axi_mst_resp_t     (cluster_narrow_out_dw_conv_resp_t),
      .axi_slv_req_t      (snitch_cluster_pkg::narrow_out_req_t),
      .axi_slv_resp_t     (snitch_cluster_pkg::narrow_out_resp_t)
    ) i_axi_dw_hwpe (
      .clk_i     (tile_clk),
      .rst_ni    (tile_rst_n),
      .slv_req_i (cluster_narrow_ext_req),
      .slv_resp_o(cluster_narrow_ext_rsp),
      .mst_req_o (cluster_narrow_out_dw_conv_req),
      .mst_resp_i(cluster_narrow_out_dw_conv_rsp)
    );

    axi_cut #(
      .Bypass    (0),
      .aw_chan_t (snitch_cluster_pkg::narrow_out_aw_chan_t),
      .w_chan_t  (cluster_narrow_out_dw_conv_w_chan_t),
      .b_chan_t  (snitch_cluster_pkg::narrow_out_b_chan_t),
      .ar_chan_t (snitch_cluster_pkg::narrow_out_ar_chan_t),
      .r_chan_t  (cluster_narrow_out_dw_conv_r_chan_t),
      .axi_req_t (cluster_narrow_out_dw_conv_req_t),
      .axi_resp_t(cluster_narrow_out_dw_conv_resp_t)
    ) i_cut_ext_narrow_slv (
      .clk_i     (tile_clk),
      .rst_ni    (tile_rst_n),
      .slv_req_i (cluster_narrow_out_dw_conv_req),
      .slv_resp_o(cluster_narrow_out_dw_conv_rsp),
      .mst_req_o (cluster_narrow_out_cut_req),
      .mst_resp_i(cluster_narrow_out_cut_rsp)
    );

    axi_to_tcdm #(
      .axi_req_t (cluster_narrow_out_dw_conv_req_t),
      .axi_rsp_t (cluster_narrow_out_dw_conv_resp_t),
      .tcdm_req_t(hwpectrl_req_t),
      .tcdm_rsp_t(hwpectrl_rsp_t),
      .IdWidth   (snitch_cluster_pkg::NarrowIdWidthOut),
      .AddrWidth (HWPECtrlAddrWidth),
      .DataWidth (HWPECtrlDataWidth)
    ) i_axi_to_hwpe_ctrl (
      .clk_i     (tile_clk),
      .rst_ni    (tile_rst_n),
      .axi_req_i (cluster_narrow_out_cut_req),
      .axi_rsp_o (cluster_narrow_out_cut_rsp),
      .tcdm_req_o(hwpectrl_req),
      .tcdm_rsp_i(hwpectrl_rsp)
    );

    snitch_tcdm_aligner #(
      .tcdm_req_t   (snitch_cluster_pkg::tcdm_dma_req_t),
      .tcdm_rsp_t   (snitch_cluster_pkg::tcdm_dma_rsp_t),
      .DataWidth    (snitch_cluster_pkg::WideDataWidth),
      .TCDMDataWidth(snitch_cluster_pkg::NarrowDataWidth),
      .AddrWidth    (snitch_cluster_pkg::TcdmAddrWidth)
    ) i_snitch_tcdm_aligner (
      .clk_i                (tile_clk),
      .rst_ni               (tile_rst_n),
      .tcdm_req_misaligned_i(cluster_tcdm_ext_req_misaligned),
      .tcdm_req_aligned_o   (cluster_tcdm_ext_req_aligned),
      .tcdm_rsp_aligned_i   (cluster_tcdm_ext_rsp_aligned),
      .tcdm_rsp_misaligned_o(cluster_tcdm_ext_rsp_misaligned)
    );

    snitch_hwpe_subsystem #(
      .tcdm_req_t   (snitch_cluster_pkg::tcdm_dma_req_t),
      .tcdm_rsp_t   (snitch_cluster_pkg::tcdm_dma_rsp_t),
      .periph_req_t (hwpectrl_req_t),
      .periph_rsp_t (hwpectrl_rsp_t),
      .HwpeDataWidth(snitch_cluster_pkg::WideDataWidth),
      .IdWidth      (snitch_cluster_pkg::NarrowIdWidthOut),
      .NrCores      (NrCores),
      .TCDMDataWidth(snitch_cluster_pkg::NarrowDataWidth)
    ) i_snitch_hwpe_subsystem (
      .clk_i          (tile_clk),
      .rst_ni         (tile_rst_n),
      .test_mode_i    (1'b0),
      .tcdm_req_o     (cluster_tcdm_ext_req_misaligned),
      .tcdm_rsp_i     (cluster_tcdm_ext_rsp_misaligned),
      .hwpe_ctrl_req_i(hwpectrl_req),
      .hwpe_ctrl_rsp_o(hwpectrl_rsp),
      .hwpe_evt_o     (mxip)
    );
  end else begin : gen_no_redmul_e
    assign mxip                         = '0;
    assign cluster_tcdm_ext_req_aligned = '0;
    assign cluster_narrow_ext_rsp       = '0;
  end

  ////////////
  // Router //
  ////////////

  // floo_req_t [Eject:North] router_floo_req_out, router_floo_req_in;
  // floo_rsp_t [Eject:North] router_floo_rsp_out, router_floo_rsp_in;
  // floo_wide_t [Eject:North] router_floo_wide_out, router_floo_wide_in;

  floo_req_t [Eject:North] router_floo_req_outA, router_floo_req_outB, router_floo_req_outC, router_floo_req_inA, router_floo_req_inB, router_floo_req_inC;
  floo_rsp_t [Eject:North] router_floo_rsp_outA, router_floo_rsp_outB, router_floo_rsp_outC, router_floo_rsp_inA, router_floo_rsp_inB, router_floo_rsp_inC;
  floo_wide_t [Eject:North] router_floo_wide_outA, router_floo_wide_outB, router_floo_wide_outC, router_floo_wide_inA, router_floo_wide_inB, router_floo_wide_inC;

  floo_nw_routerTMR #(
    .AxiCfgN     (AxiCfgN),
    .AxiCfgW     (AxiCfgW),
    .EnMultiCast (RouteCfg.EnMultiCast),
    .RouteAlgo   (RouteCfg.RouteAlgo),
    .NumRoutes   (5),
    .InFifoDepth (2),
    .OutFifoDepth(2),
    .id_t        (id_t),
    .hdr_t       (hdr_t),
    .floo_req_t  (floo_req_t),
    .floo_rsp_t  (floo_rsp_t),
    .floo_wide_t (floo_wide_t)
  ) i_router (
    .clk_iA (clk_i),
    .clk_iB (clk_i),
    .clk_iC (clk_i),
    .rst_niA (rst_ni),
    .rst_niB (rst_ni),
    .rst_niC (rst_ni),
    .test_enable_iA (test_enable_i),
    .test_enable_iB (test_enable_i),
    .test_enable_iC (test_enable_i),
    .id_iA         (id_i),
    .id_iB         (id_i),
    .id_iC         (id_i),
    .id_route_map_iA('0),
    .id_route_map_iB('0),
    .id_route_map_iC('0),
    .floo_req_iA   (router_floo_req_inA),
    .floo_req_iB   (router_floo_req_inB),
    .floo_req_iC   (router_floo_req_inC),
    .floo_rsp_oA   (router_floo_rsp_outA),
    .floo_rsp_oB   (router_floo_rsp_outB),
    .floo_rsp_oC   (router_floo_rsp_outC),
    .floo_req_oA   (router_floo_req_outA),
    .floo_req_oB   (router_floo_req_outB),
    .floo_req_oC   (router_floo_req_outC),
    .floo_rsp_iA   (router_floo_rsp_inA),
    .floo_rsp_iB   (router_floo_rsp_inB),
    .floo_rsp_iC   (router_floo_rsp_inC),
    .floo_wide_iA  (router_floo_wide_inA),
    .floo_wide_iB  (router_floo_wide_inB),
    .floo_wide_iC  (router_floo_wide_inC),
    .floo_wide_oA  (router_floo_wide_outA),
    .floo_wide_oB  (router_floo_wide_outB),
    .floo_wide_oC  (router_floo_wide_outC),
    .tmrErrorA    (),
    .tmrErrorB    (),
    .tmrErrorC    ()
  );

  assign floo_req_oA                      = router_floo_req_outA[West:North];
  assign floo_req_oB                      = router_floo_req_outB[West:North];
  assign floo_req_oC                      = router_floo_req_outC[West:North];
  assign router_floo_req_inA[West:North]  = floo_req_iA;
  assign router_floo_req_inB[West:North]  = floo_req_iB;
  assign router_floo_req_inC[West:North]  = floo_req_iC;
  assign floo_rsp_oA                      = router_floo_rsp_outA[West:North];
  assign floo_rsp_oB                      = router_floo_rsp_outB[West:North];
  assign floo_rsp_oC                      = router_floo_rsp_outC[West:North];
  assign router_floo_rsp_inA[West:North]  = floo_rsp_iA;
  assign router_floo_rsp_inB[West:North]  = floo_rsp_iB;
  assign router_floo_rsp_inC[West:North]  = floo_rsp_iC;
  assign floo_wide_oA                     = router_floo_wide_outA[West:North];
  assign floo_wide_oB                     = router_floo_wide_outB[West:North];
  assign floo_wide_oC                     = router_floo_wide_outC[West:North];
  assign router_floo_wide_inA[West:North] = floo_wide_iA;
  assign router_floo_wide_inB[West:North] = floo_wide_iB;
  assign router_floo_wide_inC[West:North] = floo_wide_iC;

  /////////////
  // Chimney //
  /////////////
  floo_req_t router_floo_req_in_Eject, router_floo_req_out_Eject;
  floo_rsp_t router_floo_rsp_in_Eject, router_floo_rsp_out_Eject;
  floo_wide_t router_floo_wide_in_Eject, router_floo_wide_out_Eject;

  assign router_floo_req_out_Eject = (router_floo_req_outA[Eject] & router_floo_req_outB[Eject]) | 
                                     (router_floo_req_outA[Eject] & router_floo_req_outC[Eject]) | 
                                     (router_floo_req_outB[Eject] & router_floo_req_outC[Eject]);
  assign router_floo_rsp_out_Eject = (router_floo_rsp_outA[Eject] & router_floo_rsp_outB[Eject]) | 
                                     (router_floo_rsp_outA[Eject] & router_floo_rsp_outC[Eject]) | 
                                     (router_floo_rsp_outB[Eject] & router_floo_rsp_outC[Eject]);
  assign router_floo_wide_out_Eject = (router_floo_wide_outA[Eject] & router_floo_wide_outB[Eject]) | 
                                      (router_floo_wide_outA[Eject] & router_floo_wide_outC[Eject]) | 
                                      (router_floo_wide_outB[Eject] & router_floo_wide_outC[Eject]);
  assign router_floo_req_inA[Eject] = router_floo_req_in_Eject;
  assign router_floo_req_inB[Eject] = router_floo_req_in_Eject;
  assign router_floo_req_inC[Eject] = router_floo_req_in_Eject;
  assign router_floo_rsp_inA[Eject] = router_floo_rsp_in_Eject;
  assign router_floo_rsp_inB[Eject] = router_floo_rsp_in_Eject;
  assign router_floo_rsp_inC[Eject] = router_floo_rsp_in_Eject;
  assign router_floo_wide_inA[Eject] = router_floo_wide_in_Eject;
  assign router_floo_wide_inB[Eject] = router_floo_wide_in_Eject;
  assign router_floo_wide_inC[Eject] = router_floo_wide_in_Eject;

  floo_nw_chimney #(
    .AxiCfgN             (floo_picobello_noc_pkg::AxiCfgN),
    .AxiCfgW             (floo_picobello_noc_pkg::AxiCfgW),
    .ChimneyCfgN         (floo_pkg::ChimneyDefaultCfg),
    .ChimneyCfgW         (floo_pkg::ChimneyDefaultCfg),
    .RouteCfg            (floo_picobello_noc_pkg::RouteCfg),
    .AtopSupport         (1'b1),
    .MaxAtomicTxns       (1),
    .Sam                 (floo_picobello_noc_pkg::Sam),
    .id_t                (floo_picobello_noc_pkg::id_t),
    .rob_idx_t           (floo_picobello_noc_pkg::rob_idx_t),
    .hdr_t               (floo_picobello_noc_pkg::hdr_t),
    .sam_rule_t          (floo_picobello_noc_pkg::sam_rule_t),
    // .sam_idx_t           (floo_picobello_noc_pkg::mcast_idx_t),
    // .mask_sel_t          (floo_picobello_noc_pkg::mcast_mask_sel_t),
    .axi_narrow_in_req_t (snitch_cluster_pkg::narrow_out_req_t),
    .axi_narrow_in_rsp_t (snitch_cluster_pkg::narrow_out_resp_t),
    .axi_narrow_out_req_t(snitch_cluster_pkg::narrow_in_req_t),
    .axi_narrow_out_rsp_t(snitch_cluster_pkg::narrow_in_resp_t),
    .axi_wide_in_req_t   (snitch_cluster_pkg::wide_out_req_t),
    .axi_wide_in_rsp_t   (snitch_cluster_pkg::wide_out_resp_t),
    .axi_wide_out_req_t  (snitch_cluster_pkg::wide_in_req_t),
    .axi_wide_out_rsp_t  (snitch_cluster_pkg::wide_in_resp_t),
    .floo_req_t          (floo_picobello_noc_pkg::floo_req_t),
    .floo_rsp_t          (floo_picobello_noc_pkg::floo_rsp_t),
    .floo_wide_t         (floo_picobello_noc_pkg::floo_wide_t),
    .sram_cfg_t          (snitch_cluster_pkg::sram_cfg_t)
    // .user_struct_t       (floo_picobello_noc_pkg::mcast_axi_narrow_in_user_t)
  ) i_chimney (
    .clk_i               (tile_clk),
    .rst_ni              (tile_rst_n),
    .test_enable_i,
    .id_i,
    .route_table_i       ('0),
    .sram_cfg_i          ('0),
    .axi_narrow_in_req_i (cluster_narrow_out_req),
    .axi_narrow_in_rsp_o (cluster_narrow_out_rsp),
    .axi_narrow_out_req_o(cluster_narrow_in_req),
    .axi_narrow_out_rsp_i(cluster_narrow_in_rsp),
    .axi_wide_in_req_i   (cluster_wide_out_req),
    .axi_wide_in_rsp_o   (cluster_wide_out_rsp),
    .axi_wide_out_req_o  (cluster_wide_in_req),
    .axi_wide_out_rsp_i  (cluster_wide_in_rsp),
    .floo_req_o          (router_floo_req_in_Eject),
    .floo_rsp_o          (router_floo_rsp_in_Eject),
    .floo_wide_o         (router_floo_wide_in_Eject),
    .floo_req_i          (router_floo_req_out_Eject),
    .floo_rsp_i          (router_floo_rsp_out_Eject),
    .floo_wide_i         (router_floo_wide_out_Eject)
  );

  //////////////////////////
  // Clock Gating & Reset //
  //////////////////////////

  tc_clk_gating i_tc_clk_gating_cluster (
    .clk_i,
    .en_i     (tile_clk_en_i),
    .test_en_i(clk_rst_bypass_i),
    .clk_o    (tile_clk)
  );

`ifdef TARGET_XILINX
  // Using clk cells makes Vivado flag the reset as a clock tree
  assign tile_rst_n = (clk_rst_bypass_i) ? rst_ni : tile_rst_ni;
`else
  tc_clk_mux2 i_tc_reset_mux (
    .clk0_i   (tile_rst_ni),
    .clk1_i   (rst_ni),
    .clk_sel_i(clk_rst_bypass_i),
    .clk_o    (tile_rst_n)
  );
`endif



endmodule
