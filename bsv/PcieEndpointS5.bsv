// Copyright (c) 2014 Cornell University

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package PcieEndpointS5;

import Clocks            ::*;
import Vector            ::*;
import Connectable       ::*;
import GetPut            ::*;
import Reserved          ::*;
import TieOff            ::*;
import DefaultValue      ::*;
import DReg              ::*;
import Gearbox           ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import ClientServer      ::*;
import Real              ::*;

import PCIE              ::*;
import PcieEndpointS5Lib ::*;
import PcieEndpointS5Test ::*;

(* always_ready, always_enabled *)
interface PciewrapPci_exp#(numeric type lanes);
(* prefix="", result="tx_p" *) method Bit#(lanes) tx_p();
(* prefix="", result="rx_p" *) method Action rx_p(Bit#(lanes) rx_p);
endinterface

(* always_ready, always_enabled *)
interface PciewrapUser#(numeric type lanes);
   interface Clock clk_out;
   interface Reset reset_out;
   method Bit#(1) lnk_up();
   method Bit#(1) app_rdy();
endinterface

(* always_ready, always_enabled *)
interface PciewrapCfg#(numeric type lanes);
   method Bit#(8) bus_number();
   method Bit#(5) device_number();
   method Bit#(3) function_number();
endinterface

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////

interface PcieEndpointS5#(numeric type lanes);
   interface PciewrapPci_exp#(lanes)   pcie;
   interface PciewrapUser#(lanes)      user;
   interface PciewrapCfg#(lanes)       cfg;
   interface Server#(TLPData#(16), TLPData#(16)) tlp;
   interface Clock epClock125;
   interface Reset epReset125;
   interface Clock epClock250;
   interface Reset epReset250;
   interface Clock epDerivedClock;
   interface Reset epDerivedReset;
endinterface

typedef struct {
   Bit#(1)               sop;
   Bit#(1)               eop;
   Bit#(bytes)           be;
   Bit#(TMul#(bytes, 8)) data;
} AvalonStRx#(type bytes) deriving (Bits, Eq);

typedef struct {
   Bit#(1)               sop;
   Bit#(1)               eop;
   Bit#(bytes)           be;
   Bit#(TMul#(bytes, 8)) data;
} AvalonStTx#(type bytes) deriving (Bits, Eq);

`ifdef BOARD_de5
typedef 8 PcieLanes;
typedef 4 NumLeds;
`endif

//(* synthesize *)
module mkPcieEndpointS5#(Clock clk_100MHz, Clock clk_50MHz, Reset perst_n)(PcieEndpointS5#(PcieLanes));

   PCIEParams params = defaultValue;

   Clock default_clock <- exposeCurrentClock;
   Reset default_reset <- exposeCurrentReset;
   Reset reset_high <- invertCurrentReset;
   Reset npor = perst_n; //No soft reset signal from Application

   PcieS5Wrap#(12, 32, 128) pcie_ep <- mkPcieS5Wrap(clk_100MHz, clk_50MHz, npor, perst_n);

   // Test Altera Application
//   PcieS5App pcie_app <- mkPcieS5App(pcie_ep.coreclkout_hip, reset_high);
//   mkConnection(pcie_app, pcie_ep);

   AlteraPcieHipRs hip_rs <- mkAlteraPcieHipRs(pcie_ep.coreclkout_hip, perst_n);
   AlteraPcieTlCfgSample tl_cfg <- mkAlteraPcieTlCfgSample(pcie_ep.coreclkout_hip, hip_rs.app_rstn);

   FIFOF#(AvalonStTx#(16)) fAvalonStTx <- mkBypassFIFOF(clocked_by pcie_ep.coreclkout_hip, reset_by noReset);
   FIFOF#(AvalonStRx#(16)) fAvalonStRx <- mkBypassFIFOF(clocked_by pcie_ep.coreclkout_hip, reset_by noReset);

   let txready = (pcie_ep.tx_st.ready != 0 && fAvalonStTx.notEmpty);

   //(* fire_when_enabled, no_implicit_conditions *)
   rule drive_avalon_tx if (txready);
      let info = fAvalonStTx.first; fAvalonStTx.deq;
      pcie_ep.tx_st.valid(1);
      pcie_ep.tx_st.sop(info.sop);
      pcie_ep.tx_st.eop(info.eop);
      pcie_ep.tx_st.data(info.data);
   endrule

   (* fire_when_enabled, no_implicit_conditions *)
   rule drive_avalon_tx2 if (!txready);
      pcie_ep.tx_st.valid(0);
      pcie_ep.tx_st.sop(0);
      pcie_ep.tx_st.eop(0);
      pcie_ep.tx_st.data(0);
   endrule

   (* fire_when_enabled *)
   rule sink_avalon_rx if (pcie_ep.rx_st.valid != 0);
      fAvalonStRx.enq(AvalonStRx{
         sop: pcie_ep.rx_st.sop,
         eop: pcie_ep.rx_st.eop,
         be:  pcie_ep.rx_st.be,
         data: pcie_ep.rx_st.data });
   endrule

   rule connect_configuration_signals;
      tl_cfg.tl_cfg_add(pcie_ep.tl.cfg_add);
      tl_cfg.tl_cfg_ctl(pcie_ep.tl.cfg_ctl);
      tl_cfg.tl_cfg_sts(pcie_ep.tl.cfg_sts);
   endrule

   rule connect_hip_rs;
      hip_rs.dlup_exit(pcie_ep.hip_status.dlup_exit);
      hip_rs.hotrst_exit(pcie_ep.hip_status.hotrst);
      hip_rs.l2_exit(pcie_ep.hip_status.l2_exit);
      hip_rs.ltssm(pcie_ep.hip_status.ltssmstate);
   endrule

   interface PciewrapCfg cfg;
      method Bit#(8) bus_number;
         return tl_cfg.cfg_busdev[12:5];
      endmethod
      method Bit#(5) device_number;
         return tl_cfg.cfg_busdev[4:0];
      endmethod
      method Bit#(3) function_number;
         return 0;
      endmethod
   endinterface

   interface PciewrapUser user;
      method Reset reset_out;
         return hip_rs.app_rstn;
      endmethod
      method Clock clk_out();
         return pcie_ep.coreclkout_hip;
      endmethod
      method Bit#(1) lnk_up();
         return pcie_ep.hip_rst.serdes_pll_locked;
      endmethod
      method Bit#(1) app_rdy();
         return pcie_ep.hip_rst.pld_clk_inuse;
      endmethod
   endinterface

   interface PciewrapPci_exp pcie;
      Bit#(PcieLanes) vt = pack(pcie_ep.tx.out);
      //{pcie_ep.tx.out7, pcie_ep.tx.out6, pcie_ep.tx.out5, pcie_ep.tx.out4, pcie_ep.tx.out3, pcie_ep.tx.out2, pcie_ep.tx.out1, pcie_ep.tx.out0};
      method Bit#(PcieLanes) tx_p();
         return vt;
      endmethod
      method Action rx_p(Bit#(PcieLanes) v);
         action
            pcie_ep.rx.in(unpack(v));
//            pcie_ep.rx.in0(v[0]);
//            pcie_ep.rx.in1(v[1]);
//            pcie_ep.rx.in2(v[2]);
//            pcie_ep.rx.in3(v[3]);
//            pcie_ep.rx.in4(v[4]);
//            pcie_ep.rx.in5(v[5]);
//            pcie_ep.rx.in6(v[6]);
//            pcie_ep.rx.in7(v[7]);
         endaction
      endmethod
   endinterface

   // The PCIE endpoint is processing TLPData#(16)s at 125MHz.  The
   // AXI bridge is accepting TLPData#(16)s at 125 MHz. For gen1 and
   // gen2, there is no need for gearbox conversion.
   // coreclkout_hip depends on link width, data rate and width of APP/TL interface
   // Link Width  |  Link Rate  |   Avalon Interface Width  |  coreclkout_hip
   //     x8            gen1                128 bit               125 Mhz
   //     x8            gen2                128 bit               250 Mhz
   //     x8            gen3                256 bit               250 Mhz
   interface Server tlp;
     // #(TLPData#(16), TLPData#(16)) tlp = (interface Server;
      interface Put request;
         method Action put(TLPData#(16) data);
            fAvalonStTx.enq(AvalonStTx {
               eop: pack(data.eof),
               sop: pack(data.sof),
               be:  pack(data.be),
               data: pack(data.data)
            });
         endmethod
      endinterface
      interface Get response;
         method ActionValue#(TLPData#(16)) get();
            let info <- toGet(fAvalonStRx).get;
            TLPData#(16) retval = defaultValue;
            retval.sof = (info.sop == 1);
            retval.eof = (info.eop == 1);
            retval.be = info.be;
            retval.data = info.data;
            return retval;
         endmethod
      endinterface
   endinterface

   //FIXME: verify epClock250 is needed.
   interface Clock epClock250 = pcie_ep.coreclkout_hip;
   interface Clock epReset250 = hip_rs.app_rstn;
   interface Clock epClock125 = pcie_ep.coreclkout_hip;
   interface Clock epReset125 = hip_rs.app_rstn;

   //FIXME: verify derivedClock value
   interface Clock epDerivedClock = pcie_ep.coreclkout_hip;
   interface Reset epDerivedReset = hip_rs.app_rstn;

endmodule: mkPcieEndpointS5

endpackage: PcieEndpointS5