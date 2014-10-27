// bsv libraries
import Vector::*;
import FIFO::*;
import Connectable::*;

// portz libraries
import Portal::*;
import CtrlMux::*;
import Leds::*;
import MemTypes::*;
import HostInterface::*;


// generated by tool
import EchoIndicationProxy::*;
import EchoRequestWrapper::*;
import SwallowWrapper::*;

// defined by user
import Echo::*;
import Swallow::*;

typedef enum {EchoIndication, EchoRequest, Swallow} IfcNames deriving (Eq,Bits);

// module mkCntr#(Integer label)(Empty);
//    Reg#(Bit#(32)) cycles <- mkReg(0);
//    rule count;
//       cycles <= cycles+1;
//       $display("mkCntr(%d) %d",label, cycles);
//    endrule
// endmodule

module mkConnectalTop#(HostType host)(StdConnectalTop#(PhysAddrWidth));

   // instantiate user portals
   EchoIndicationProxy echoIndicationProxy <- mkEchoIndicationProxy(EchoIndication);
   EchoRequestInternal echoRequestInternal <- mkEchoRequestInternal(echoIndicationProxy.ifc);
   EchoRequestWrapper echoRequestWrapper <- mkEchoRequestWrapper(EchoRequest,echoRequestInternal.ifc);
   
   // let cnt0 <- mkCntr(0);
   // let cnt1 <- mkCntr(1, clocked_by host.doubleClock, reset_by host.doubleReset);

   Swallow swallow <- mkSwallow();
   SwallowWrapper swallowWrapper <- mkSwallowWrapper(Swallow, swallow);
   
   Vector#(3,StdPortal) portals;
   portals[0] = swallowWrapper.portalIfc; 
   portals[1] = echoRequestWrapper.portalIfc; 
   portals[2] = echoIndicationProxy.portalIfc;
   let ctrl_mux <- mkSlaveMux(portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = nil;
   interface leds = echoRequestInternal.leds;
   interface Empty pins;
   endinterface

endmodule : mkConnectalTop
