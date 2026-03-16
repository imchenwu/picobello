// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Lorenzo Leone <lleone@iis.ee.ethz.ch>

`include "axi/assign.svh"

module dummy_tileTMR
  import floo_pkg::*;
  import floo_picobello_noc_pkg::*;
  import picobello_pkg::*;
(
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_enable_i,
  input  id_t                     id_i,
  output floo_req_t  [West:North] floo_req_oA,
  output floo_req_t  [West:North] floo_req_oB,
  output floo_req_t  [West:North] floo_req_oC,
  input  floo_rsp_t  [West:North] floo_rsp_iA,
  input  floo_rsp_t  [West:North] floo_rsp_iB,
  input  floo_rsp_t  [West:North] floo_rsp_iC,
  output floo_wide_t [West:North] floo_wide_oA,
  output floo_wide_t [West:North] floo_wide_oB,
  output floo_wide_t [West:North] floo_wide_oC,
  input  floo_req_t  [West:North] floo_req_iA,
  input  floo_req_t  [West:North] floo_req_iB,
  input  floo_req_t  [West:North] floo_req_iC,
  output floo_rsp_t  [West:North] floo_rsp_oA,
  output floo_rsp_t  [West:North] floo_rsp_oB,
  output floo_rsp_t  [West:North] floo_rsp_oC,
  input  floo_wide_t [West:North] floo_wide_iA,
  input  floo_wide_t [West:North] floo_wide_iB,
  input  floo_wide_t [West:North] floo_wide_iC
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
    .RouteAlgo   (RouteCfgNoMcast.RouteAlgo),
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
    .floo_wide_oC   (router_floo_wide_outC),
    .tmrErrorA      (),
    .tmrErrorB      (),
    .tmrErrorC      ()
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

  // Tie the router’s Eject input ports to 0
  assign router_floo_req_inA[Eject]      = '0;
  assign router_floo_req_inB[Eject]      = '0;
  assign router_floo_req_inC[Eject]      = '0;
  assign router_floo_rsp_inA[Eject]      = '0;
  assign router_floo_rsp_inB[Eject]      = '0;
  assign router_floo_rsp_inC[Eject]      = '0;
  assign router_floo_wide_inA[Eject]     = '0;
  assign router_floo_wide_inB[Eject]     = '0;
  assign router_floo_wide_inC[Eject]     = '0;


endmodule : dummy_tileTMR
