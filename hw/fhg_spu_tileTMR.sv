// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Riccardo Fiorani Gallotta <riccardo.fiorani3@unibo.it>

`include "axi/assign.svh"

module fhg_spu_tileTMR
  import floo_pkg::*;
  import floo_picobello_noc_pkg::*;
  import picobello_pkg::*;
(
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            test_enable_i,
  input  logic                            tile_clk_en_i,
  input  logic                            tile_rst_ni,
  input  logic                            clk_rst_bypass_i,
  // Cluster ports
  input  logic                      [8:0] debug_req_i,
  input  logic                      [8:0] meip_i,
  input  logic                      [8:0] mtip_i,
  input  logic                      [8:0] msip_i,
  input  logic                      [9:0] hart_base_id_i,
  input  snitch_cluster_pkg::addr_t       cluster_base_addr_i,
  // Chimney ports
  input  id_t                             id_i,
  // Router ports
  output floo_req_t                       floo_req_west_oA,
  output floo_req_t                       floo_req_west_oB,
  output floo_req_t                       floo_req_west_oC,
  input  floo_rsp_t                       floo_rsp_west_iA,
  input  floo_rsp_t                       floo_rsp_west_iB,
  input  floo_rsp_t                       floo_rsp_west_iC,
  output floo_wide_t                      floo_wide_west_oA,
  output floo_wide_t                      floo_wide_west_oB,
  output floo_wide_t                      floo_wide_west_oC,
  input  floo_req_t                       floo_req_west_iA,
  input  floo_req_t                       floo_req_west_iB,
  input  floo_req_t                       floo_req_west_iC,
  output floo_rsp_t                       floo_rsp_west_oA,
  output floo_rsp_t                       floo_rsp_west_oB,
  output floo_rsp_t                       floo_rsp_west_oC,
  input  floo_wide_t                      floo_wide_west_iA,
  input  floo_wide_t                      floo_wide_west_iB,
  input  floo_wide_t                      floo_wide_west_iC,
  output floo_req_t                       floo_req_north_oA,
  output floo_req_t                       floo_req_north_oB,
  output floo_req_t                       floo_req_north_oC,
  input  floo_rsp_t                       floo_rsp_north_iA,
  input  floo_rsp_t                       floo_rsp_north_iB,
  input  floo_rsp_t                       floo_rsp_north_iC,
  output floo_wide_t                      floo_wide_north_oA,
  output floo_wide_t                      floo_wide_north_oB,
  output floo_wide_t                      floo_wide_north_oC,
  input  floo_req_t                       floo_req_north_iA,
  input  floo_req_t                       floo_req_north_iB,
  input  floo_req_t                       floo_req_north_iC,
  output floo_rsp_t                       floo_rsp_north_oA,
  output floo_rsp_t                       floo_rsp_north_oB,
  output floo_rsp_t                       floo_rsp_north_oC,
  input  floo_wide_t                      floo_wide_north_iA,
  input  floo_wide_t                      floo_wide_north_iB,
  input  floo_wide_t                      floo_wide_north_iC
);

  ////////////
  // Router //
  ////////////

  floo_req_t [Eject:North] router_floo_req_outA, router_floo_req_outB, router_floo_req_outC,
                          router_floo_req_inA, router_floo_req_inB, router_floo_req_inC;
  floo_rsp_t [Eject:North] router_floo_rsp_outA, router_floo_rsp_outB, router_floo_rsp_outC,
                          router_floo_rsp_inA, router_floo_rsp_inB, router_floo_rsp_inC;
  floo_wide_t [Eject:North] router_floo_wide_outA, router_floo_wide_outB, router_floo_wide_outC,
                           router_floo_wide_inA, router_floo_wide_inB, router_floo_wide_inC;

  floo_nw_routerTMR #(
    .AxiCfgN     (AxiCfgN),
    .AxiCfgW     (AxiCfgW),
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
    .clk_iA         (clk_i),
    .clk_iB         (clk_i),
    .clk_iC         (clk_i),
    .rst_niA        (rst_ni),
    .rst_niB        (rst_ni),
    .rst_niC        (rst_ni),
    .test_enable_iA (test_enable_i),
    .test_enable_iB (test_enable_i),
    .test_enable_iC (test_enable_i),
    .id_iA          (id_i),
    .id_iB          (id_i),
    .id_iC          (id_i),
    .id_route_map_iA('0),
    .id_route_map_iB('0),
    .id_route_map_iC('0),
    .floo_req_iA    (router_floo_req_inA),
    .floo_req_iB    (router_floo_req_inB),
    .floo_req_iC    (router_floo_req_inC),
    .floo_rsp_oA    (router_floo_rsp_outA),
    .floo_rsp_oB    (router_floo_rsp_outB),
    .floo_rsp_oC    (router_floo_rsp_outC),
    .floo_req_oA    (router_floo_req_outA),
    .floo_req_oB    (router_floo_req_outB),
    .floo_req_oC    (router_floo_req_outC),
    .floo_rsp_iA    (router_floo_rsp_inA),
    .floo_rsp_iB    (router_floo_rsp_inB),
    .floo_rsp_iC    (router_floo_rsp_inC),
    .floo_wide_iA   (router_floo_wide_inA),
    .floo_wide_iB   (router_floo_wide_inB),
    .floo_wide_iC   (router_floo_wide_inC),
    .floo_wide_oA   (router_floo_wide_outA),
    .floo_wide_oB   (router_floo_wide_outB),
    .floo_wide_oC   (router_floo_wide_outC)
  `ifdef TARGET_FTMR
    , .tmrErrorA       (              )
    , .tmrErrorB       (              )
    , .tmrErrorC       (              )
  `endif
  );

  assign floo_req_west_oA            = router_floo_req_outA[West];
  assign floo_req_west_oB            = router_floo_req_outB[West];
  assign floo_req_west_oC            = router_floo_req_outC[West];
  assign floo_req_north_oA           = router_floo_req_outA[North];
  assign floo_req_north_oB           = router_floo_req_outB[North];
  assign floo_req_north_oC           = router_floo_req_outC[North];
  assign router_floo_req_inA[West]   = floo_req_west_iA;
  assign router_floo_req_inB[West]   = floo_req_west_iB;
  assign router_floo_req_inC[West]   = floo_req_west_iC;
  assign router_floo_req_inA[South]  = '0;  // No South port in this tile
  assign router_floo_req_inB[South]  = '0;  // No South port in this tile
  assign router_floo_req_inC[South]  = '0;  // No South port in this tile
  assign router_floo_req_inA[East]   = '0;  // No East port in this tile
  assign router_floo_req_inB[East]   = '0;  // No East port in this tile
  assign router_floo_req_inC[East]   = '0;  // No East port in this tile
  assign router_floo_req_inA[North]  = floo_req_north_iA;
  assign router_floo_req_inB[North]  = floo_req_north_iB;
  assign router_floo_req_inC[North]  = floo_req_north_iC;
  assign floo_rsp_west_oA            = router_floo_rsp_outA[West];
  assign floo_rsp_west_oB            = router_floo_rsp_outB[West];
  assign floo_rsp_west_oC            = router_floo_rsp_outC[West];
  assign floo_rsp_north_oA           = router_floo_rsp_outA[North];
  assign floo_rsp_north_oB           = router_floo_rsp_outB[North];
  assign floo_rsp_north_oC           = router_floo_rsp_outC[North];
  assign router_floo_rsp_inA[West]   = floo_rsp_west_iA;
  assign router_floo_rsp_inB[West]   = floo_rsp_west_iB;
  assign router_floo_rsp_inC[West]   = floo_rsp_west_iC;
  assign router_floo_rsp_inA[South]  = '0;  // No South port in this tile
  assign router_floo_rsp_inB[South]  = '0;  // No South port in this tile
  assign router_floo_rsp_inC[South]  = '0;  // No South port in this tile
  assign router_floo_rsp_inA[East]   = '0;  // No East port in this tile
  assign router_floo_rsp_inB[East]   = '0;  // No East port in this tile
  assign router_floo_rsp_inC[East]   = '0;  // No East port in this tile
  assign router_floo_rsp_inA[North]  = floo_rsp_north_iA;
  assign router_floo_rsp_inB[North]  = floo_rsp_north_iB;
  assign router_floo_rsp_inC[North]  = floo_rsp_north_iC;
  assign floo_wide_west_oA           = router_floo_wide_outA[West];
  assign floo_wide_west_oB           = router_floo_wide_outB[West];
  assign floo_wide_west_oC           = router_floo_wide_outC[West];
  assign floo_wide_north_oA          = router_floo_wide_outA[North];
  assign floo_wide_north_oB          = router_floo_wide_outB[North];
  assign floo_wide_north_oC          = router_floo_wide_outC[North];
  assign router_floo_wide_inA[West]  = floo_wide_west_iA;
  assign router_floo_wide_inB[West]  = floo_wide_west_iB;
  assign router_floo_wide_inC[West]  = floo_wide_west_iC;
  assign router_floo_wide_inA[South] = '0;  // No South port in this tile
  assign router_floo_wide_inB[South] = '0;  // No South port in this tile
  assign router_floo_wide_inC[South] = '0;  // No South port in this tile
  assign router_floo_wide_inA[East]  = '0;  // No East port in this tile
  assign router_floo_wide_inB[East]  = '0;  // No East port in this tile
  assign router_floo_wide_inC[East]  = '0;  // No East port in this tile
  assign router_floo_wide_inA[North] = floo_wide_north_iA;
  assign router_floo_wide_inB[North] = floo_wide_north_iB;
  assign router_floo_wide_inC[North] = floo_wide_north_iC;

  // It's actually a dummy tile: tie the router’s Eject input ports to 0
  assign router_floo_req_inA[Eject]  = '0;
  assign router_floo_req_inB[Eject]  = '0;
  assign router_floo_req_inC[Eject]  = '0;
  assign router_floo_rsp_inA[Eject]  = '0;
  assign router_floo_rsp_inB[Eject]  = '0;
  assign router_floo_rsp_inC[Eject]  = '0;
  assign router_floo_wide_inA[Eject] = '0;
  assign router_floo_wide_inB[Eject] = '0;
  assign router_floo_wide_inC[Eject] = '0;

endmodule : fhg_spu_tileTMR
