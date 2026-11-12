package Hydronic
  "The parts of a hydronic heating plant: bodies of fluid, and the pipes, valves and pumps that join them"

  connector VolumePort
    "Where a body of fluid is joined to: the pressure and temperature here are the body's own"
    Real p(unit = "Pa") "Pressure above the loop's expansion vessel";
    flow Real q(unit = "m3/s") "Volume flow into the component";
    Real T(unit = "K");
    flow Real H(unit = "W") "Heat the flow carries into the component, counted from 0 K";
    annotation(Icon(graphics = {Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 90, 180}, fillColor = {0, 90, 180}, fillPattern = FillPattern.Solid)}));
  end VolumePort;

  connector FlowPort
    "An end of a pipe, valve or pump: its temperature is that of the body of fluid it is joined to"
    Real p(unit = "Pa") "Pressure above the loop's expansion vessel";
    flow Real q(unit = "m3/s") "Volume flow into the component";
    Real T(unit = "K");
    flow Real H(unit = "W") "Heat the flow carries into the component, counted from 0 K";
    annotation(Icon(graphics = {Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid, lineThickness = 0.5)}));
  end FlowPort;

  connector RealInput = input Real "A signal into a component"
    annotation(Icon(graphics = {Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {0, 0, 127}, fillPattern = FillPattern.Solid)}),
      Diagram(graphics = {
        Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {0, 0, 127}, fillPattern = FillPattern.Solid),
        Text(extent = {{-1500, -50}, {-130, 50}}, textString = "%name", textColor = {0, 0, 127}, horizontalAlignment = TextAlignment.Right)}));

  connector RealOutput = output Real "A signal out of a component"
    annotation(Icon(graphics = {Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid)}),
      Diagram(graphics = {
        Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
        Text(extent = {{130, -50}, {1500, 50}}, textString = "%name", textColor = {0, 0, 127}, horizontalAlignment = TextAlignment.Left)}));

  function bilinear
    "Bilinear interpolation on a rectangular grid, held at the edge values outside it"
    input Real x;
    input Real y;
    input Real xGrid[:];
    input Real yGrid[:];
    input Real table[size(xGrid, 1), size(yGrid, 1)];
    output Real z;
  protected
    Real xc = min(max(x, xGrid[1]), xGrid[end]);
    Real yc = min(max(y, yGrid[1]), yGrid[end]);
    Integer i = 1;
    Integer j = 1;
    Real u;
    Real v;
  algorithm
    while i < size(xGrid, 1) - 1 and xc > xGrid[i + 1] loop
      i := i + 1;
    end while;
    while j < size(yGrid, 1) - 1 and yc > yGrid[j + 1] loop
      j := j + 1;
    end while;
    u := (xc - xGrid[i]) / (xGrid[i + 1] - xGrid[i]);
    v := (yc - yGrid[j]) / (yGrid[j + 1] - yGrid[j]);
    z := (1 - u) * (1 - v) * table[i, j] + u * (1 - v) * table[i + 1, j]
       + (1 - u) * v * table[i, j + 1] + u * v * table[i + 1, j + 1];
  end bilinear;

  function counterflowEffectiveness
    "Effectiveness of a counterflow exchanger from its transfer units and capacity-rate ratio"
    input Real ntu;
    input Real capacityRatio;
    output Real effectiveness;
  protected
    Real decay;
  algorithm
    if abs(1 - capacityRatio) < 1e-4 then
      effectiveness := ntu / (1 + ntu);
    else
      decay := exp(-ntu * (1 - capacityRatio));
      effectiveness := (1 - decay) / (1 - capacityRatio * decay);
    end if;
  end counterflowEffectiveness;

  function meterReading
    "What a flow meter shows: the size of the flow, and nothing below the least it can turn on"
    input Real q(unit = "m3/s");
    input Real qMin(unit = "m3/s");
    output Real reading(unit = "m3/s");
  algorithm
    reading := if abs(q) < qMin then 0 else abs(q);
  end meterReading;

  partial model FlowElement
    "Fluid passing from one body of fluid to another through a part that holds none: what leaves it is what entered"
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the fluid by volume";
    FlowPort port_a annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    FlowPort port_b annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
    Real q(unit = "m3/s") "Flow from port_a to port_b";
  equation
    q = port_a.q;
    port_a.q + port_b.q = 0;
    port_a.H = c * (noEvent(max(q, 0)) * port_a.T - noEvent(max(-q, 0)) * port_b.T);
    port_a.H + port_b.H = 0;
  end FlowElement;

  model Pipe
    "A run of pipe with no pressure drop of its own: its drop is counted in the valve or resistance of its branch"
    extends FlowElement;
  equation
    port_a.p = port_b.p;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -25}, {100, 25}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, 40}, {300, 100}}, textString = "%name", textColor = {0, 0, 0})}));
  end Pipe;

  model Resistance "The pressure drop of a branch of pipework, in proportion to its flow"
    extends FlowElement;
    parameter Real dpNominal(unit = "Pa") "Pressure drop at VFlowNominal";
    parameter Real VFlowNominal(unit = "m3/s") "Flow at which dpNominal is given";
  equation
    port_a.p - port_b.p = dpNominal / VFlowNominal * q;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -25}, {100, 25}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{-70, 0}, {-50, 50}, {-25, -50}, {0, 50}, {25, -50}, {50, 50}, {70, 0}}, color = {0, 0, 0}, thickness = 0.5),
      Text(extent = {{-300, 60}, {300, 120}}, textString = "%name", textColor = {0, 0, 0})}));
  end Resistance;

  model Valve
    "A motorised valve and the pipework of its branch: the branch's pressure drop when open, and a leak when closed"
    extends FlowElement;
    parameter Real dpNominal(unit = "Pa") "Pressure drop of the branch at VFlowNominal with the valve open";
    parameter Real VFlowNominal(unit = "m3/s") "Flow at which dpNominal is given";
    parameter Real leakage "Conductance when closed as a fraction of the conductance when open";
    RealInput position "0 closed, 1 open" annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real opening = min(max(position, 0), 1);
  equation
    q = (leakage + (1 - leakage) * opening) * VFlowNominal / dpNominal * (port_a.p - port_b.p);
    annotation(Icon(graphics = {
      Polygon(points = {{-100, 50}, {-100, -50}, {0, 0}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{100, 50}, {100, -50}, {0, 0}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{0, 0}, {0, 90}}, color = {0, 0, 0}),
      Text(extent = {{-300, -120}, {300, -60}}, textString = "%name", textColor = {0, 0, 0})}));
  end Valve;

  partial model Circulator
    "What a circulator does to the water: its head falls in proportion to its flow, and both rise with its speed"
    extends FlowElement;
    parameter Real dpShutoff(unit = "Pa") "Head at full speed and no flow";
    parameter Real VFlowMax(unit = "m3/s") "Flow at full speed and no head";
    parameter Real PNominal(unit = "W") "Electrical power at full speed";
    RealInput on "Its relay: 0 off, 1 on" annotation(Placement(transformation(origin = {-60, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealInput speed "Speed as a fraction of full" annotation(Placement(transformation(origin = {60, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real running = min(max(on, 0), 1) * min(max(speed, 0), 1) "Speed as a fraction of full, zero while off";
    Real power(unit = "W") = PNominal * running ^ 3;
    Real head(unit = "Pa") = dpShutoff * running ^ 2 - dpShutoff / VFlowMax * q "Pressure the impeller adds";
    annotation(Icon(graphics = {
      Ellipse(extent = {{-90, -90}, {90, 90}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-35, 70}, {85, 0}, {-35, -70}}, lineColor = {0, 90, 180}, fillColor = {0, 90, 180}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -160}, {300, -100}}, textString = "%name", textColor = {0, 0, 0})}));
  end Circulator;
  model Pump "A circulator: its head falls in proportion to its flow, and both rise with its speed"
    extends Circulator;
  equation
    port_b.p - port_a.p = head;
  end Pump;

  model CheckedPump
    "A circulator with a spring check valve at its outlet: next to nothing passes backwards through it, running or stopped"
    extends Circulator;
    parameter Real dpCheckNominal(unit = "Pa") "Pressure drop of the check valve beyond its cracking pressure at VFlowNominal";
    parameter Real VFlowNominal(unit = "m3/s") "Flow at which dpCheckNominal is given";
    parameter Real dpCrack(unit = "Pa") "Pressure across the check valve at which it opens";
    parameter Real leakage "Conductance of the shut check valve as a fraction of its open conductance";
    Real dpCheck(unit = "Pa") "Pressure drop across the check valve";
  equation
    port_b.p - port_a.p = head - dpCheck;
    q = VFlowNominal / dpCheckNominal * (leakage * dpCheck + (1 - leakage) * max(dpCheck - dpCrack, 0));
    annotation(Icon(graphics = {
      Line(points = {{90, -60}, {90, 60}}, color = {0, 0, 0}, thickness = 1)}));
  end CheckedPump;

  model Volume
    "A well-mixed body of fluid at one pressure, losing heat to its surroundings: a header, a tee, a sensed run of pipe, a boiler"
    parameter Real C(unit = "J/K") "Heat capacity of the fluid and what holds it";
    parameter Real UA(unit = "W/K") "Loss to the surroundings";
    parameter Real TSurroundings(unit = "K");
    parameter Real TStart(unit = "K") "Temperature at time zero";
    VolumePort port_a annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    VolumePort port_b annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
    Real T(unit = "K", start = TStart, fixed = true);
    Real QLoss(unit = "W") = UA * (T - TSurroundings);
    Real E(unit = "J") = C * (T - 273.15) "Heat held, above 0 degC";
  equation
    port_a.T = T;
    port_b.T = T;
    port_a.p = port_b.p;
    port_a.q + port_b.q = 0;
    C * der(T) = port_a.H + port_b.H - QLoss;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -60}, {100, 60}}, radius = 40, lineColor = {0, 90, 180}, fillColor = {85, 170, 255}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, 70}, {300, 130}}, textString = "%name", textColor = {0, 0, 0})}));
  end Volume;

  model Tank
    "A store tank in layers that keep their stratification, mixing only where a warmer layer lies under a colder one"
    parameter Integer nLayers = 9 "Layers, top first";
    parameter Integer sensorLayer[:] = {2, 5, 8} "Layer read by each depth sensor, top first";
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the water by volume";
    parameter Real V(unit = "m3");
    parameter Real height(unit = "m") "Water height";
    parameter Real UA(unit = "W/K") "Loss to the surroundings";
    parameter Real kEffective(unit = "W/(m.K)") "Vertical conduction through water and wall";
    parameter Real tauBuoyancy(unit = "s") "Time for a layer lying under a colder one to mix with it";
    parameter Real TSurroundings(unit = "K");
    parameter Real TStart(unit = "K") "Temperature of every layer at time zero";
    VolumePort top annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}})));
    VolumePort bottom annotation(Placement(transformation(origin = {0, -100}, extent = {{-10, -10}, {10, 10}})));
    Real T[nLayers](each unit = "K", each start = TStart, each fixed = true);
    Real TSensor[size(sensorLayer, 1)](each unit = "K") = {T[sensorLayer[i]] for i in 1:size(sensorLayer, 1)};
    Real QLoss(unit = "W") = UALayer * (sum(T) - nLayers * TSurroundings);
    Real E(unit = "J") = CLayer * (sum(T) - nLayers * 273.15) "Heat held, above 0 degC";
  protected
    parameter Real CLayer(unit = "J/K") = c * V / nLayers;
    parameter Real UALayer(unit = "W/K") = UA / nLayers;
    parameter Real GConduction(unit = "W/K") = kEffective * (V / height) / (height / nLayers);
    parameter Real GBuoyancy(unit = "W/K") = CLayer / tauBuoyancy;
    Real qDown(unit = "m3/s") = noEvent(max(top.q, 0));
    Real qUp(unit = "m3/s") = noEvent(max(-top.q, 0));
    Real HDown[nLayers - 1](each unit = "W") "Heat the flow carries from a layer to the one beneath it";
    Real QDown[nLayers - 1](each unit = "W") "Heat passing from a layer to the one beneath it by conduction and mixing";
  equation
    top.T = T[1];
    bottom.T = T[nLayers];
    top.p = bottom.p;
    top.q + bottom.q = 0;
    for i in 1:nLayers - 1 loop
      HDown[i] = c * (qDown * T[i] - qUp * T[i + 1]);
      QDown[i] = GConduction * (T[i] - T[i + 1]) - GBuoyancy * noEvent(max(T[i + 1] - T[i], 0));
    end for;
    CLayer * der(T[1]) = top.H - HDown[1] - QDown[1] - UALayer * (T[1] - TSurroundings);
    for i in 2:nLayers - 1 loop
      CLayer * der(T[i]) = HDown[i - 1] - HDown[i] + QDown[i - 1] - QDown[i] - UALayer * (T[i] - TSurroundings);
    end for;
    CLayer * der(T[nLayers]) = HDown[nLayers - 1] + bottom.H + QDown[nLayers - 1]
      - UALayer * (T[nLayers] - TSurroundings);
    annotation(Icon(graphics = {
      Rectangle(extent = {{-80, -90}, {80, 90}}, radius = 30, lineColor = {0, 90, 180}, fillColor = {85, 170, 255}, fillPattern = FillPattern.VerticalCylinder),
      Line(points = {{-80, 45}, {80, 45}}, color = {255, 255, 255}),
      Line(points = {{-80, 0}, {80, 0}}, color = {255, 255, 255}),
      Line(points = {{-80, -45}, {80, -45}}, color = {255, 255, 255}),
      Text(extent = {{-300, -140}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end Tank;

  model Expansion
    "An expansion vessel: it holds the loop it is joined to at the pressure the loop's others are measured from, and no fluid passes"
    FlowPort port annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}})));
  equation
    port.p = 0;
    port.H = 0;
    annotation(Icon(graphics = {
      Line(points = {{0, 90}, {0, 40}}, color = {0, 90, 180}),
      Ellipse(extent = {{-60, -80}, {60, 40}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{-58, -20}, {58, -20}}, color = {0, 90, 180}),
      Text(extent = {{-300, -140}, {300, -90}}, textString = "%name", textColor = {0, 0, 0})}));
  end Expansion;

  partial model HeatPumpCycle
    "A heat pump's compressor and the fluid in its condenser: heat output and COP by outdoor and leaving temperature, and a compressor that stops at a leaving-temperature limit"
    parameter Real C(unit = "J/K") "Fluid and metal in the condenser";
    parameter Real TLwtMax(unit = "K") "Leaving temperature at which the compressor stops";
    parameter Real dTLwtRestart(unit = "K") "Fall below TLwtMax at which the compressor may restart";
    parameter Real TOutdoorGrid[:](each unit = "K");
    parameter Real TLwtGrid[:](each unit = "K");
    parameter Real QTable[size(TOutdoorGrid, 1), size(TLwtGrid, 1)](each unit = "W") "Heat output by outdoor and leaving temperature";
    parameter Real COPTable[size(TOutdoorGrid, 1), size(TLwtGrid, 1)] "Heat out over compressor power in, by outdoor and leaving temperature";
    parameter Real TStart(unit = "K") "Temperature at time zero";
    Real T(unit = "K", start = TStart, fixed = true) "Fluid leaving";
    Boolean lwtPermit(start = true, fixed = true);
    Real compressor "1 while the compressor runs";
    Real Q(unit = "W") "Heat put into the fluid";
    Real PCompressor(unit = "W");
    Real E(unit = "J") = C * (T - 273.15) "Heat held, above 0 degC";
  protected
    Real asked "1 while the compressor is asked to run";
    Real TAir(unit = "K") "Outdoor air";
  equation
    lwtPermit = if pre(lwtPermit) then T < TLwtMax else T < TLwtMax - dTLwtRestart;
    compressor = asked * (if lwtPermit then 1 else 0);
    Q = compressor * bilinear(TAir, T, TOutdoorGrid, TLwtGrid, QTable);
    PCompressor = Q / bilinear(TAir, T, TOutdoorGrid, TLwtGrid, COPTable);
  end HeatPumpCycle;

  model HeatPump "A monobloc heat pump with the glycol pump it owns"
    extends HeatPumpCycle;
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the glycol by volume";
    parameter Real VFlowNominal(unit = "m3/s") "Glycol flow while the heat pump is called";
    parameter Real UA(unit = "W/K") "Loss of the condenser and outdoor pipe to the outdoor air";
    parameter Real PStandby(unit = "W") "Outdoor unit with the compressor stopped";
    parameter Real PControlBoxStandby(unit = "W");
    parameter Real PPump(unit = "W") "Glycol pump, on the control box";
    FlowPort inlet annotation(Placement(transformation(origin = {100, -75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort outlet annotation(Placement(transformation(origin = {100, 75}, extent = {{-10, -10}, {10, 10}})));
    RealInput call "The scada's call: 0 no call, 1 call" annotation(Placement(transformation(origin = {-100, 50}, extent = {{-10, -10}, {10, 10}})));
    RealInput scadaControl "Who holds the call: 0 the aquastat, which makes none here, 1 the scada" annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}})));
    RealInput TOutdoor(unit = "K") annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real enable = min(max(call, 0), 1) * min(max(scadaControl, 0), 1);
    Real q(unit = "m3/s") = VFlowNominal * enable "Glycol flow";
    Real oduPower(unit = "W") = PCompressor + PStandby;
    Real ctrlBoxPower(unit = "W") = PControlBoxStandby + PPump * enable;
    Real QLoss(unit = "W") = UA * (T - TOutdoor);
  equation
    asked = enable;
    TAir = TOutdoor;
    inlet.q = q;
    inlet.H = c * q * inlet.T;
    outlet.q = -q;
    outlet.T = T;
    C * der(T) = inlet.H + outlet.H + Q - QLoss;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {225, 225, 225}, fillPattern = FillPattern.Solid),
      Ellipse(extent = {{-60, -45}, {40, 55}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{-10, 5}, {-10, 55}}, color = {0, 0, 0}),
      Line(points = {{-10, 5}, {33, -20}}, color = {0, 0, 0}),
      Line(points = {{-10, 5}, {-53, -20}}, color = {0, 0, 0}),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end HeatPump;

  model SplitHeatPump
    "The indoor unit of a split heat pump, its water moved by a pump elsewhere that it calls for: the compressor runs only while water flows"
    extends HeatPumpCycle;
    parameter Real UA(unit = "W/K") "Loss of the indoor unit to its surroundings";
    parameter Real TSurroundings(unit = "K");
    parameter Real VFlowMin(unit = "m3/s") "Water flow below which the compressor does not run";
    parameter Real indoorShare "Share of the compressor power drawn by the indoor unit";
    parameter Real PStandbyOutdoor(unit = "W") "Outdoor unit with the compressor stopped";
    parameter Real PStandbyIndoor(unit = "W") "Indoor unit with the compressor stopped";
    VolumePort inlet annotation(Placement(transformation(origin = {-100, -75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort outlet annotation(Placement(transformation(origin = {-100, -25}, extent = {{-10, -10}, {10, 10}})));
    RealInput call "The scada's call: 0 no call, 1 call" annotation(Placement(transformation(origin = {-50, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealInput scadaControl "Who holds the call: 0 the aquastat, which makes none here, 1 the scada" annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealInput TOutdoor(unit = "K") annotation(Placement(transformation(origin = {50, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealOutput pumpCall "Its call for the pump that moves its water: 1 while it is called" annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Real enable = min(max(call, 0), 1) * min(max(scadaControl, 0), 1);
    Real q(unit = "m3/s") = inlet.q "Water flow";
    Boolean flowPermit = q > VFlowMin;
    Real oduPower(unit = "W") = (1 - indoorShare) * PCompressor + PStandbyOutdoor;
    Real iduPower(unit = "W") = indoorShare * PCompressor + PStandbyIndoor;
    Real QLoss(unit = "W") = UA * (T - TSurroundings);
  equation
    asked = enable * (if flowPermit then 1 else 0);
    pumpCall = enable;
    TAir = TOutdoor;
    inlet.T = T;
    outlet.T = T;
    inlet.p = outlet.p;
    inlet.q + outlet.q = 0;
    C * der(T) = inlet.H + outlet.H + Q - QLoss;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{-60, 0}, {60, 80}}, lineColor = {0, 0, 0}, fillColor = {40, 40, 40}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end SplitHeatPump;

  model PlateExchanger
    "A counterflow plate exchanger between the glycol and the water, each side a body of fluid of its own"
    parameter Real cGlycol(unit = "J/(m3.K)") "Heat capacity of the glycol by volume";
    parameter Real cWater(unit = "J/(m3.K)") "Heat capacity of the water by volume";
    parameter Real UA(unit = "W/K") "Conductance at design flow";
    parameter Real UAStatic(unit = "W/K") "Conduction across the plates with no flow";
    parameter Real CSide(unit = "J/K") "Fluid and plate on one side";
    parameter Real UALoss(unit = "W/K") "Loss of each side to the surroundings";
    parameter Real TSurroundings(unit = "K");
    parameter Real TStart(unit = "K") "Temperature of both sides at time zero";
    constant Real capacityFloor(unit = "W/K") = 1e-3 "Capacity rate below which a side counts as still";
    VolumePort glycol_a annotation(Placement(transformation(origin = {-100, 75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort glycol_b annotation(Placement(transformation(origin = {-100, -75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort water_a annotation(Placement(transformation(origin = {100, -75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort water_b annotation(Placement(transformation(origin = {100, 75}, extent = {{-10, -10}, {10, 10}})));
    Real TGlycol(unit = "K", start = TStart, fixed = true);
    Real TWater(unit = "K", start = TStart, fixed = true);
    Real capacityGlycol(unit = "W/K") = cGlycol * noEvent(abs(glycol_a.q));
    Real capacityWater(unit = "W/K") = cWater * noEvent(abs(water_a.q));
    Real capacityMin(unit = "W/K") = noEvent(min(capacityGlycol, capacityWater));
    Real capacityMax(unit = "W/K") = noEvent(max(capacityGlycol, capacityWater));
    Real HGlycolIn(unit = "W") = noEvent(max(glycol_a.H, glycol_b.H)) "Heat the entering glycol carries";
    Real HWaterIn(unit = "W") = noEvent(max(water_a.H, water_b.H)) "Heat the entering water carries";
    Real Q(unit = "W") "Heat passing from glycol to water";
    Real QLoss(unit = "W") = UALoss * (TGlycol + TWater - 2 * TSurroundings);
    Real E(unit = "J") = CSide * (TGlycol + TWater - 2 * 273.15) "Heat held, above 0 degC";
  equation
    glycol_a.T = TGlycol;
    glycol_b.T = TGlycol;
    glycol_a.p = glycol_b.p;
    glycol_a.q + glycol_b.q = 0;
    water_a.T = TWater;
    water_b.T = TWater;
    water_a.p = water_b.p;
    water_a.q + water_b.q = 0;
    Q = counterflowEffectiveness(
        UA / max(capacityMin, capacityFloor),
        max(capacityMin, capacityFloor) / max(capacityMax, capacityFloor))
      * capacityMin * (HGlycolIn / max(capacityGlycol, capacityFloor) - HWaterIn / max(capacityWater, capacityFloor))
      + UAStatic * (TGlycol - TWater);
    CSide * der(TGlycol) = glycol_a.H + glycol_b.H - Q - UALoss * (TGlycol - TSurroundings);
    CSide * der(TWater) = water_a.H + water_b.H + Q - UALoss * (TWater - TSurroundings);
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{-100, 75}, {-10, 75}, {-10, -75}, {-100, -75}}, color = {160, 60, 160}, thickness = 0.5),
      Line(points = {{100, -75}, {10, -75}, {10, 75}, {100, 75}}, color = {0, 90, 180}, thickness = 0.5),
      Line(points = {{0, 95}, {0, -95}}, color = {0, 0, 0}),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end PlateExchanger;

  partial model ZoneSet
    "The zones of a house in parallel between a supply and a return, each a thermostat with a deadband, a zone valve, an emitter and a room"
    parameter Integer nZones = 4;
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the water by volume";
    parameter Real dpZoneNominal(unit = "Pa") "One zone's valve and emitter at VFlowZoneNominal";
    parameter Real VFlowZoneNominal(unit = "m3/s") "Flow at which dpZoneNominal is given";
    parameter Real leakage "Conductance of a closed zone valve as a fraction of its open conductance";
    parameter Real CEmitter(unit = "J/K") "Water and metal of one zone's emitters";
    parameter Real UAEmitter(unit = "W/K") "One zone's emitters to its room";
    parameter Real CZone(unit = "J/K") "Air and fabric of one zone as a single lump";
    parameter Real UAZone(unit = "W/K") "One zone to the outdoor air";
    parameter Real TZoneSet(unit = "K") "Thermostat setpoint";
    parameter Real dTZoneDeadband(unit = "K") "Thermostat swing, centred on the setpoint";
    parameter Real PZoneValve(unit = "W") "Power on a zone's thermostat wire while it calls";
    parameter Real TStartEmitter(unit = "K") "Every emitter at time zero";
    parameter Real TStartZone(unit = "K") "Every zone at time zero";
    FlowPort supply annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}})));
    FlowPort ret annotation(Placement(transformation(origin = {0, -100}, extent = {{-10, -10}, {10, 10}})));
    RealInput TOutdoor(unit = "K") annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}})));
    Real TEmitter[nZones](each unit = "K", each start = TStartEmitter, each fixed = true);
    Real TZone[nZones](each unit = "K", each start = TStartZone, each fixed = true);
    Boolean calling[nZones](each start = false, each fixed = true) "Each thermostat's call";
    Real position[nZones] "Zone valves: 0 closed, 1 open";
    Real anyOpen "1 while a zone valve is open";
    Real qZone[nZones](each unit = "m3/s") "Flow through each zone, supply to return";
    Real q(unit = "m3/s") "Flow through all the zones";
    Real callPower[nZones](each unit = "W") = PZoneValve * position;
    Real QLoss(unit = "W") = UAZone * (sum(TZone) - nZones * TOutdoor);
    Real E(unit = "J") = CEmitter * (sum(TEmitter) - nZones * 273.15) + CZone * (sum(TZone) - nZones * 273.15) "Heat held, above 0 degC";
  protected
    Real pManifold(unit = "Pa") "Zone outlets";
    Real qIn[nZones](each unit = "m3/s") = {noEvent(max(qZone[i], 0)) for i in 1:nZones};
    Real qBack[nZones](each unit = "m3/s") = {noEvent(max(-qZone[i], 0)) for i in 1:nZones};
  equation
    for i in 1:nZones loop
      calling[i] = if pre(calling[i]) then TZone[i] < TZoneSet + dTZoneDeadband / 2
        else TZone[i] < TZoneSet - dTZoneDeadband / 2;
      qZone[i] = (leakage + (1 - leakage) * position[i]) * VFlowZoneNominal / dpZoneNominal * (supply.p - pManifold);
      CEmitter * der(TEmitter[i]) = c * (qIn[i] * (supply.T - TEmitter[i]) + qBack[i] * (ret.T - TEmitter[i]))
        - UAEmitter * (TEmitter[i] - TZone[i]);
      CZone * der(TZone[i]) = UAEmitter * (TEmitter[i] - TZone[i]) - UAZone * (TZone[i] - TOutdoor);
    end for;
    anyOpen = min(sum(position), 1);
    q = sum(qZone);
    supply.q = q;
    ret.q = -q;
    supply.H = c * sum(qIn[i] * supply.T - qBack[i] * TEmitter[i] for i in 1:nZones);
    ret.H = c * sum(qBack[i] * ret.T - qIn[i] * TEmitter[i] for i in 1:nZones);
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 244, 214}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-100, 100}, {0, 150}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 244, 214}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{-60, 10}, {-40, 70}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{-30, 10}, {-10, 70}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{10, 10}, {30, 70}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{40, 10}, {60, 70}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end ZoneSet;

  model ZonedDistribution
    "The zones of a house with the one circulator, downstream of them, that draws water through whichever call"
    extends ZoneSet;
    parameter Real dpPumpShutoff(unit = "Pa") "Head of the circulator at full speed and no flow";
    parameter Real VFlowPumpMax(unit = "m3/s") "Flow of the circulator at full speed and no head";
    parameter Real PPumpNominal(unit = "W") "Circulator at full speed";
    RealInput speed "Circulator speed as a fraction of full" annotation(Placement(transformation(origin = {-100, 50}, extent = {{-10, -10}, {10, 10}})));
    Real pumpPower(unit = "W") = PPumpNominal * min(max(speed, 0), 1) ^ 3 * anyOpen;
  equation
    for i in 1:nZones loop
      position[i] = if calling[i] then 1 else 0;
    end for;
    ret.p - pManifold = dpPumpShutoff * min(max(speed, 0), 1) ^ 2 * anyOpen - dpPumpShutoff / VFlowPumpMax * q;
    annotation(Icon(graphics = {
      Ellipse(extent = {{-25, -75}, {25, -25}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-18, -35}, {0, -75}, {18, -35}}, lineColor = {0, 90, 180}, fillColor = {0, 90, 180}, fillPattern = FillPattern.Solid)}));
  end ZonedDistribution;

  model Zones
    "The zones of a house whose circulator is a part of its own: each zone valve follows its thermostat, or the scada while the scada holds that zone"
    extends ZoneSet;
    RealInput scadaControl[nZones] "Who holds each zone's call: 0 its thermostat, 1 the scada" annotation(Placement(transformation(origin = {30, -100}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    RealInput scadaCall[nZones] "The scada's call for each zone: 0 no call, 1 call" annotation(Placement(transformation(origin = {70, -100}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    RealOutput call "1 while a zone valve is open, which is when the circulator is to run" annotation(Placement(transformation(origin = {100, -50}, extent = {{-10, -10}, {10, 10}})));
  equation
    for i in 1:nZones loop
      position[i] = if scadaControl[i] > 0.5 then (if scadaCall[i] > 0.5 then 1 else 0) else (if calling[i] then 1 else 0);
    end for;
    pManifold = ret.p;
    call = anyOpen;
  end Zones;

  model CheckValve
    "A spring check valve and the pipework of its branch: flow from port_a to port_b once the pressure across it passes its cracking pressure, and a leak otherwise"
    extends FlowElement;
    parameter Real dpNominal(unit = "Pa") "Pressure drop of the branch beyond the cracking pressure at VFlowNominal";
    parameter Real VFlowNominal(unit = "m3/s") "Flow at which dpNominal is given";
    parameter Real dpCrack(unit = "Pa") "Pressure across the valve at which it opens";
    parameter Real leakage "Conductance when shut as a fraction of the conductance when open";
  equation
    q = VFlowNominal / dpNominal * (leakage * (port_a.p - port_b.p) + (1 - leakage) * max(port_a.p - port_b.p - dpCrack, 0));
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -25}, {100, 25}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-50, 50}, {-50, -50}, {40, 0}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{40, -50}, {40, 50}}, color = {0, 0, 0}, thickness = 1),
      Text(extent = {{-300, 60}, {300, 120}}, textString = "%name", textColor = {0, 0, 0})}));
  end CheckValve;

  model FlowMeter "A flow meter in a run of pipe with no pressure drop of its own"
    extends FlowElement;
    parameter Real VFlowMin(unit = "m3/s") "Flow below which the meter reads zero";
    Real reading(unit = "m3/s") = meterReading(q, VFlowMin);
  equation
    port_a.p = port_b.p;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -25}, {100, 25}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Ellipse(extent = {{-60, -60}, {60, 60}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{0, 0}, {35, 35}}, color = {0, 0, 0}, thickness = 0.5),
      Text(extent = {{-300, 70}, {300, 130}}, textString = "%name", textColor = {0, 0, 0})}));
  end FlowMeter;

  model ThreeWayValve
    "A motorised three-way valve, its branches and the water in its body: the common port is open to the rest leg at position 0 and to the driven leg at position 1, and to both in proportion between"
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the fluid by volume";
    parameter Real C(unit = "J/K") "Heat capacity of the fluid in the body and what holds it";
    parameter Real UA(unit = "W/K") "Loss to the surroundings";
    parameter Real TSurroundings(unit = "K");
    parameter Real TStart(unit = "K") "Temperature at time zero";
    parameter Real dpRestNominal(unit = "Pa") "Pressure drop of the rest leg and its branch at VFlowNominal with the leg open";
    parameter Real dpDrivenNominal(unit = "Pa") "Pressure drop of the driven leg and its branch at VFlowNominal with the leg open";
    parameter Real VFlowNominal(unit = "m3/s") "Flow at which the pressure drops are given";
    parameter Real leakage "Conductance of a closed leg as a fraction of its open conductance";
    VolumePort common annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
    FlowPort rest "Open to the common port at position 0" annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    FlowPort driven "Open to the common port at position 1" annotation(Placement(transformation(origin = {0, -100}, extent = {{-10, -10}, {10, 10}})));
    RealInput position "0 at rest, 1 fully driven" annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real opening = min(max(position, 0), 1);
    Real T(unit = "K", start = TStart, fixed = true);
    Real qRest(unit = "m3/s") "Flow from the body out through the rest leg";
    Real qDriven(unit = "m3/s") "Flow from the body out through the driven leg";
    Real QLoss(unit = "W") = UA * (T - TSurroundings);
    Real E(unit = "J") = C * (T - 273.15) "Heat held, above 0 degC";
  equation
    common.T = T;
    qRest = (leakage + (1 - leakage) * (1 - opening)) * VFlowNominal / dpRestNominal * (common.p - rest.p);
    qDriven = (leakage + (1 - leakage) * opening) * VFlowNominal / dpDrivenNominal * (common.p - driven.p);
    rest.q = -qRest;
    driven.q = -qDriven;
    common.q = qRest + qDriven;
    rest.H = c * (noEvent(max(-qRest, 0)) * rest.T - noEvent(max(qRest, 0)) * T);
    driven.H = c * (noEvent(max(-qDriven, 0)) * driven.T - noEvent(max(qDriven, 0)) * T);
    C * der(T) = common.H + rest.H + driven.H - QLoss;
    annotation(Icon(graphics = {
      Polygon(points = {{-100, 50}, {-100, -50}, {0, 0}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{100, 50}, {100, -50}, {0, 0}}, lineColor = {0, 90, 180}, fillColor = {85, 170, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-50, -100}, {50, -100}, {0, 0}}, lineColor = {0, 90, 180}, fillColor = {170, 213, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{0, 0}, {0, 90}}, color = {0, 0, 0}),
      Text(extent = {{-400, 110}, {-30, 170}}, textString = "%name", textColor = {0, 0, 0}, horizontalAlignment = TextAlignment.Right)}));
  end ThreeWayValve;

  block ValveMotor
    "The motor of a valve that travels between two stops at a steady rate, slowing into each, and the position its travel gives the valve"
    parameter Real travel(unit = "s") "Motor time from the rest stop to the driven stop";
    parameter Real tOnset(unit = "s") "Motor time from the rest stop at which the valve begins to leave its rest position";
    parameter Real tComplete(unit = "s") "Motor time from the rest stop at which the valve is fully driven";
    parameter Real tStart(unit = "s") "Motor time from the rest stop at time zero";
    constant Real tSettle(unit = "s") = 1 "Motor time from a stop within which the travel slows";
    RealInput on "0 stopped, 1 running" annotation(Placement(transformation(origin = {-100, 50}, extent = {{-10, -10}, {10, 10}})));
    RealInput toward "Which way it runs: 0 toward the rest stop, 1 toward the driven stop" annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}})));
    RealOutput position "0 at rest, 1 fully driven" annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
    Real t(unit = "s", start = tStart, fixed = true) "Motor time from the rest stop";
  equation
    der(t) = if on > 0.5 then (if toward > 0.5 then noEvent(min(1, (travel - t) / tSettle)) else -noEvent(min(1, t / tSettle))) else 0;
    position = min(max((t - tOnset) / (tComplete - tOnset), 0), 1);
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 127}, fillColor = {214, 228, 245}, fillPattern = FillPattern.Solid),
      Text(extent = {{-80, -70}, {80, 70}}, textString = "M", textColor = {0, 0, 0})}));
  end ValveMotor;

  block Complement "One less its input: the position of a valve that closes as another opens"
    RealInput u annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    RealOutput y annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
  equation
    y = 1 - u;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 127}, fillColor = {214, 228, 245}, fillPattern = FillPattern.Solid),
      Text(extent = {{-90, -60}, {90, 60}}, textString = "1-u", textColor = {0, 0, 0})}));
  end Complement;

  block Changeover "A double-throw relay: it passes u0 while its control is 0 and u1 while it is 1"
    RealInput u0 annotation(Placement(transformation(origin = {-100, 60}, extent = {{-10, -10}, {10, 10}})));
    RealInput u1 annotation(Placement(transformation(origin = {-100, -60}, extent = {{-10, -10}, {10, 10}})));
    RealInput control annotation(Placement(transformation(origin = {0, -100}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    RealOutput y annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
  equation
    y = if control > 0.5 then u1 else u0;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 127}, fillColor = {214, 228, 245}, fillPattern = FillPattern.Solid),
      Line(points = {{-90, 60}, {-40, 60}}, color = {0, 0, 127}),
      Line(points = {{-90, -60}, {-40, -60}}, color = {0, 0, 127}),
      Line(points = {{-40, 60}, {40, 0}, {90, 0}}, color = {0, 0, 127})}));
  end Changeover;

  block Aquastat
    "A thermostat on water: it calls from a fall below its setting until the water is back at it, unless it is held off"
    parameter Real TSet(unit = "K") "Water temperature at which the call ends";
    parameter Real dT(unit = "K") "Fall below TSet at which the call begins";
    RealInput T(unit = "K") "The water it senses" annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealInput held "0 free to call, 1 held off" annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    RealOutput call "0 no call, 1 call" annotation(Placement(transformation(origin = {100, 0}, extent = {{-10, -10}, {10, 10}})));
    Boolean cold(start = false, fixed = true);
  equation
    cold = if pre(cold) then T < TSet else T < TSet - dT;
    call = if cold and held < 0.5 then 1 else 0;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 127}, fillColor = {214, 228, 245}, fillPattern = FillPattern.Solid),
      Text(extent = {{-80, -70}, {80, 70}}, textString = "T", textColor = {0, 0, 0})}));
  end Aquastat;

  model Boiler
    "A boiler as the water and iron on its branch, fired to hold its aquastat setting while it is called"
    parameter Real C(unit = "J/K") "Water and iron";
    parameter Real UA(unit = "W/K") "Loss to the surroundings";
    parameter Real TSurroundings(unit = "K");
    parameter Real TStart(unit = "K") "Temperature at time zero";
    parameter Real QBurner(unit = "W") "Heat the burner puts into the water";
    parameter Real PBurner(unit = "W") "Electrical power of the burner while it fires";
    parameter Real TAquastat(unit = "K") "Water temperature at which the burner stops";
    parameter Real dTAquastat(unit = "K") "Fall below TAquastat at which the burner fires again";
    VolumePort inlet annotation(Placement(transformation(origin = {100, -60}, extent = {{-10, -10}, {10, 10}})));
    VolumePort outlet annotation(Placement(transformation(origin = {100, 60}, extent = {{-10, -10}, {10, 10}})));
    RealInput call "0 not called, 1 called" annotation(Placement(transformation(origin = {-100, 0}, extent = {{-10, -10}, {10, 10}})));
    Real T(unit = "K", start = TStart, fixed = true);
    Boolean firing(start = false, fixed = true);
    Real Q(unit = "W") = if firing then QBurner else 0 "Heat put into the water";
    Real power(unit = "W") = if firing then PBurner else 0;
    Real QLoss(unit = "W") = UA * (T - TSurroundings);
    Real E(unit = "J") = C * (T - 273.15) "Heat held, above 0 degC";
  equation
    firing = call > 0.5 and (if pre(firing) then T < TAquastat else T < TAquastat - dTAquastat);
    inlet.T = T;
    outlet.T = T;
    inlet.p = outlet.p;
    inlet.q + outlet.q = 0;
    C * der(T) = inlet.H + outlet.H + Q - QLoss;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 225}, fillPattern = FillPattern.Solid),
      Rectangle(extent = {{-70, 20}, {70, 80}}, radius = 20, lineColor = {180, 0, 0}, fillColor = {255, 120, 120}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-40, -80}, {-20, -30}, {0, -55}, {20, -20}, {40, -80}}, lineColor = {200, 80, 0}, fillColor = {255, 200, 0}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end Boiler;
  annotation(Documentation(info = "<html><p>A filled port is a body of fluid and a hollow port is an end of a pipe, valve, resistance, meter or pump: every joint has exactly one filled port, so between two bodies of fluid there is always one part that carries the flow. No tool checks that rule.</p></html>"));
end Hydronic;
