package KatahdinComponents
  "The Katahdin heating plant as connected components: the parts, inputs, outputs and parameters of Katahdin.Plant, drawn as its pipework"

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
    annotation(Icon(graphics = {Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {0, 0, 127}, fillPattern = FillPattern.Solid)}));

  connector RealOutput = output Real "A signal out of a component"
    annotation(Icon(graphics = {Polygon(points = {{-100, 100}, {100, 0}, {-100, -100}}, lineColor = {0, 0, 127}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid)}));

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

  model Pump "A circulator: its head falls in proportion to its flow, and both rise with its speed"
    extends FlowElement;
    parameter Real dpShutoff(unit = "Pa") "Head at full speed and no flow";
    parameter Real VFlowMax(unit = "m3/s") "Flow at full speed and no head";
    parameter Real PNominal(unit = "W") "Electrical power at full speed";
    RealInput on "Its relay: 0 off, 1 on" annotation(Placement(transformation(origin = {-60, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    RealInput speed "Speed as a fraction of full" annotation(Placement(transformation(origin = {60, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real running = min(max(on, 0), 1) * min(max(speed, 0), 1) "Speed as a fraction of full, zero while off";
    Real power(unit = "W") = PNominal * running ^ 3;
  equation
    port_b.p - port_a.p = dpShutoff * running ^ 2 - dpShutoff / VFlowMax * q;
    annotation(Icon(graphics = {
      Ellipse(extent = {{-90, -90}, {90, 90}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-35, 70}, {85, 0}, {-35, -70}}, lineColor = {0, 90, 180}, fillColor = {0, 90, 180}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -160}, {300, -100}}, textString = "%name", textColor = {0, 0, 0})}));
  end Pump;

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

  model HeatPump
    "A monobloc heat pump with the glycol pump it owns: heat output and COP by outdoor and leaving glycol temperature, and a compressor that stops at a leaving-temperature limit"
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the glycol by volume";
    parameter Real VFlowNominal(unit = "m3/s") "Glycol flow while the heat pump is called";
    parameter Real C(unit = "J/K") "Glycol and metal in the condenser";
    parameter Real UA(unit = "W/K") "Loss of the condenser and outdoor pipe to the outdoor air";
    parameter Real TLwtMax(unit = "K") "Leaving glycol temperature at which the compressor stops";
    parameter Real dTLwtRestart(unit = "K") "Fall below TLwtMax at which the compressor may restart";
    parameter Real TOutdoorGrid[:](each unit = "K");
    parameter Real TLwtGrid[:](each unit = "K");
    parameter Real QTable[size(TOutdoorGrid, 1), size(TLwtGrid, 1)](each unit = "W") "Heat output by outdoor and leaving glycol temperature";
    parameter Real COPTable[size(TOutdoorGrid, 1), size(TLwtGrid, 1)] "Heat out over compressor power in, by outdoor and leaving glycol temperature";
    parameter Real PStandby(unit = "W") "Outdoor unit with the compressor stopped";
    parameter Real PControlBoxStandby(unit = "W");
    parameter Real PPump(unit = "W") "Glycol pump, on the control box";
    parameter Real TStart(unit = "K") "Temperature at time zero";
    FlowPort inlet annotation(Placement(transformation(origin = {100, -75}, extent = {{-10, -10}, {10, 10}})));
    VolumePort outlet annotation(Placement(transformation(origin = {100, 75}, extent = {{-10, -10}, {10, 10}})));
    RealInput call "The scada's call: 0 no call, 1 call" annotation(Placement(transformation(origin = {-100, 50}, extent = {{-10, -10}, {10, 10}})));
    RealInput scadaControl "Who holds the call: 0 the aquastat, which makes none here, 1 the scada" annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}})));
    RealInput TOutdoor(unit = "K") annotation(Placement(transformation(origin = {0, 100}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Real T(unit = "K", start = TStart, fixed = true) "Glycol leaving";
    Real enable = min(max(call, 0), 1) * min(max(scadaControl, 0), 1);
    Real q(unit = "m3/s") = VFlowNominal * enable "Glycol flow";
    Boolean lwtPermit(start = true, fixed = true);
    Real compressor "1 while the compressor runs";
    Real Q(unit = "W") "Heat put into the glycol";
    Real PCompressor(unit = "W");
    Real oduPower(unit = "W") = PCompressor + PStandby;
    Real ctrlBoxPower(unit = "W") = PControlBoxStandby + PPump * enable;
    Real QLoss(unit = "W") = UA * (T - TOutdoor);
    Real E(unit = "J") = C * (T - 273.15) "Heat held, above 0 degC";
  equation
    inlet.q = q;
    inlet.H = c * q * inlet.T;
    outlet.q = -q;
    outlet.T = T;
    lwtPermit = if pre(lwtPermit) then T < TLwtMax else T < TLwtMax - dTLwtRestart;
    compressor = enable * (if lwtPermit then 1 else 0);
    Q = compressor * bilinear(TOutdoor, T, TOutdoorGrid, TLwtGrid, QTable);
    PCompressor = Q / bilinear(TOutdoor, T, TOutdoorGrid, TLwtGrid, COPTable);
    C * der(T) = inlet.H + outlet.H + Q - QLoss;
    annotation(Icon(graphics = {
      Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {225, 225, 225}, fillPattern = FillPattern.Solid),
      Ellipse(extent = {{-60, -45}, {40, 55}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Line(points = {{-10, 5}, {-10, 55}}, color = {0, 0, 0}),
      Line(points = {{-10, 5}, {33, -20}}, color = {0, 0, 0}),
      Line(points = {{-10, 5}, {-53, -20}}, color = {0, 0, 0}),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end HeatPump;

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

  model ZonedDistribution
    "The house: zones in parallel, each a thermostat with a deadband, a zone valve, an emitter and a room, and the one circulator that draws water through whichever call"
    parameter Integer nZones = 4;
    parameter Real c(unit = "J/(m3.K)") "Heat capacity of the water by volume";
    parameter Real dpZoneNominal(unit = "Pa") "One zone's valve and emitter at VFlowZoneNominal";
    parameter Real VFlowZoneNominal(unit = "m3/s") "Flow at which dpZoneNominal is given";
    parameter Real leakage "Conductance of a closed zone valve as a fraction of its open conductance";
    parameter Real dpPumpShutoff(unit = "Pa") "Head of the circulator at full speed and no flow";
    parameter Real VFlowPumpMax(unit = "m3/s") "Flow of the circulator at full speed and no head";
    parameter Real PPumpNominal(unit = "W") "Circulator at full speed";
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
    FlowPort ret "Downstream of the circulator" annotation(Placement(transformation(origin = {0, -100}, extent = {{-10, -10}, {10, 10}})));
    RealInput speed "Circulator speed as a fraction of full" annotation(Placement(transformation(origin = {-100, 50}, extent = {{-10, -10}, {10, 10}})));
    RealInput TOutdoor(unit = "K") annotation(Placement(transformation(origin = {-100, -50}, extent = {{-10, -10}, {10, 10}})));
    Real TEmitter[nZones](each unit = "K", each start = TStartEmitter, each fixed = true);
    Real TZone[nZones](each unit = "K", each start = TStartZone, each fixed = true);
    Boolean calling[nZones](each start = false, each fixed = true);
    Real position[nZones] "Zone valves: 0 closed, 1 open";
    Real anyOpen "1 while a zone calls, which is when the circulator runs";
    Real qZone[nZones](each unit = "m3/s") "Flow through each zone, supply to return";
    Real q(unit = "m3/s") "Flow through the circulator";
    Real callPower[nZones](each unit = "W") = PZoneValve * position;
    Real pumpPower(unit = "W") = PPumpNominal * min(max(speed, 0), 1) ^ 3 * anyOpen;
    Real QLoss(unit = "W") = UAZone * (sum(TZone) - nZones * TOutdoor);
    Real E(unit = "J") = CEmitter * (sum(TEmitter) - nZones * 273.15) + CZone * (sum(TZone) - nZones * 273.15) "Heat held, above 0 degC";
  protected
    Real pManifold(unit = "Pa") "Zone outlets, upstream of the circulator";
    Real qIn[nZones](each unit = "m3/s") = {noEvent(max(qZone[i], 0)) for i in 1:nZones};
    Real qBack[nZones](each unit = "m3/s") = {noEvent(max(-qZone[i], 0)) for i in 1:nZones};
  equation
    for i in 1:nZones loop
      calling[i] = if pre(calling[i]) then TZone[i] < TZoneSet + dTZoneDeadband / 2
        else TZone[i] < TZoneSet - dTZoneDeadband / 2;
      position[i] = if calling[i] then 1 else 0;
      qZone[i] = (leakage + (1 - leakage) * position[i]) * VFlowZoneNominal / dpZoneNominal * (supply.p - pManifold);
      CEmitter * der(TEmitter[i]) = c * (qIn[i] * (supply.T - TEmitter[i]) + qBack[i] * (ret.T - TEmitter[i]))
        - UAEmitter * (TEmitter[i] - TZone[i]);
      CZone * der(TZone[i]) = UAEmitter * (TEmitter[i] - TZone[i]) - UAZone * (TZone[i] - TOutdoor);
    end for;
    anyOpen = min(sum(position), 1);
    q = sum(qZone);
    ret.p - pManifold = dpPumpShutoff * min(max(speed, 0), 1) ^ 2 * anyOpen - dpPumpShutoff / VFlowPumpMax * q;
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
      Ellipse(extent = {{-25, -75}, {25, -25}}, lineColor = {0, 90, 180}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
      Polygon(points = {{-18, -35}, {0, -75}, {18, -35}}, lineColor = {0, 90, 180}, fillColor = {0, 90, 180}, fillPattern = FillPattern.Solid),
      Text(extent = {{-300, -150}, {300, -110}}, textString = "%name", textColor = {0, 0, 0})}));
  end ZonedDistribution;

  model Plant
    "Valve positions, pump commands and weather in; every sensed temperature, flow and power out"

    constant Integer nZones = 4 "Zones on the distribution loop";
    constant Integer nSeg = 9 "Layers in each store tank";
    constant Integer sensorCell[3] = {2, 5, 8} "Layer read by each depth sensor of a tank, top first";

    RealInput v1Position(start = 0) "V1, exchanger to supply header: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {-110, 62}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    RealInput v2Position(start = 1) "V2, supply header to hot tank top: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {52, 120}, extent = {{-5, -5}, {5, 5}}, rotation = 180)));
    RealInput v3Position(start = 0) "V3, supply header to cold tank top: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {152, 120}, extent = {{-5, -5}, {5, 5}}, rotation = 180)));
    RealInput v4Position(start = 0) "V4, house return to return header: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {210, -172}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    RealInput v5Position(start = 0) "V5, house return to boiler: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {418, -100}, extent = {{-5, -5}, {5, 5}})));
    RealInput secondaryPumpOn(start = 0) "Pump 2 relay: 0 off, 1 on"
      annotation(Placement(transformation(origin = {-104, -62}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    RealInput secondaryPumpSpeed(start = 1) "Pump 2 speed as a fraction of full"
      annotation(Placement(transformation(origin = {-116, -62}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    RealInput distPumpSpeed(start = 1) "Distribution circulator speed as a fraction of full"
      annotation(Placement(transformation(origin = {318, 20}, extent = {{-5, -5}, {5, 5}})));
    RealInput hpEnable(start = 0) "The scada's call for the heat pump: 0 no call, 1 call"
      annotation(Placement(transformation(origin = {-362, 20}, extent = {{-5, -5}, {5, 5}})));
    RealInput hpScadaControl(start = 1) "Who holds the heat pump's call: 0 its aquastat, which makes none here, 1 the scada"
      annotation(Placement(transformation(origin = {-362, -20}, extent = {{-5, -5}, {5, 5}})));
    RealInput TOutdoor(unit = "K", start = 268.15) "Outdoor air temperature"
      annotation(Placement(transformation(origin = {-362, 170}, extent = {{-5, -5}, {5, 5}})));

    parameter Real rhoWater(unit = "kg/m3") = 990;
    parameter Real cpWater(unit = "J/(kg.K)") = 4180;
    parameter Real rhoGlycol(unit = "kg/m3") = 1017 "30% propylene glycol near 40 degC";
    parameter Real cpGlycol(unit = "J/(kg.K)") = 3870 "30% propylene glycol near 40 degC";

    parameter Real VFlowNominal(unit = "m3/s") = 3.155e-4 "Flow at which the branch pressure drops are given: 5 US gpm";
    parameter Real VFlowZoneNominal(unit = "m3/s") = 7.886e-5 "Flow at which dpZoneNominal is given: 1.25 US gpm";
    parameter Real VFlowPrimaryNominal(unit = "m3/s") = 3.155e-4 "Glycol flow while the heat pump is enabled";
    parameter Real dpPumpShutoff(unit = "Pa") = 40e3 "Head of either water pump at full speed and no flow";
    parameter Real VFlowPumpMax(unit = "m3/s") = 6.31e-4 "Flow of either water pump at full speed and no head";
    parameter Real dpSecondaryNominal(unit = "Pa") = 18.5e3 "Return header through the exchanger and V1 to the supply header";
    parameter Real dpStoreHotNominal(unit = "Pa") = 1.0e3 "Supply header through V2, the hot and the middle tank to the junction";
    parameter Real dpStoreMidNominal(unit = "Pa") = 0.5e3 "Supply header through V3 to the junction";
    parameter Real dpStoreColdNominal(unit = "Pa") = 0.5e3 "Junction through the cold tank to the return header";
    parameter Real dpSupplyNominal(unit = "Pa") = 0.5e3 "Supply header to the house supply tee";
    parameter Real dpReturnNominal(unit = "Pa") = 0.5e3 "House return tee through V4 to the return header";
    parameter Real dpBoilerNominal(unit = "Pa") = 3.0e3 "House return tee through V5 and the boiler to the supply tee";
    parameter Real dpZoneNominal(unit = "Pa") = 18.5e3 "One zone's valve and emitter at VFlowZoneNominal";
    parameter Real leakage = 1e-6 "Conductance of a closed valve as a fraction of its open conductance";
    parameter Real VFlowMeterMin(unit = "m3/s") = 1.26e-5 "Flow below which a flow meter reads zero: 0.2 US gpm";

    parameter Real VTank(unit = "m3") = 0.3 "Volume of one store tank";
    parameter Real hTank(unit = "m") = 1.5 "Water height of one store tank";
    parameter Real UATank(unit = "W/K") = 2.0 "Loss of one store tank to the room";
    parameter Real kTankEffective(unit = "W/(m.K)") = 1.5 "Vertical conduction through water and wall";
    parameter Real tauBuoyancy(unit = "s") = 30 "Time for a layer lying under a colder one to mix with it";

    parameter Real UAExchanger(unit = "W/K") = 3000 "Plate exchanger at design flow";
    parameter Real UAExchangerStatic(unit = "W/K") = 20 "Conduction across the plates with no flow";
    parameter Real CExchangerSide(unit = "J/K") = 9e3 "Fluid and plate on one side of the exchanger";
    parameter Real VVolumizer(unit = "m3") = 0.019;
    parameter Real UAVolumizer(unit = "W/K") = 0.5;
    parameter Real CHeatPump(unit = "J/K") = 22e3 "Glycol and metal in the heat pump condenser";
    parameter Real UAHeatPump(unit = "W/K") = 3.0 "Loss of the condenser and outdoor pipe to the outdoor air";
    parameter Real VPipe(unit = "m3") = 1.5e-3 "Water in each header, tee and sensed pipe run";
    parameter Real UAPipe(unit = "W/K") = 0.5 "Loss of each such run, and of each side of the exchanger, to the room";
    parameter Real CBoiler(unit = "J/K") = 233e3 "Water and iron in the boiler";
    parameter Real UABoiler(unit = "W/K") = 5.0;
    parameter Real TAmbient(unit = "K") = 291.15 "Mechanical room air";

    parameter Real TLwtMax(unit = "K") = 328.15 "Leaving glycol temperature at which the compressor stops";
    parameter Real dTLwtRestart(unit = "K") = 8 "Fall below TLwtMax at which the compressor may restart";
    parameter Real TOutdoorGrid[4](each unit = "K") = {253.15, 263.15, 273.15, 283.15};
    parameter Real TLwtGrid[3](each unit = "K") = {308.15, 318.15, 328.15};
    parameter Real QHeatPumpTable[4, 3](each unit = "W") =
      {{8000, 7500, 7000}, {10000, 9500, 9000}, {12000, 11500, 11000}, {14000, 13500, 13000}}
      "Heat output by outdoor and leaving glycol temperature";
    parameter Real COPTable[4, 3] =
      {{2.4, 2.0, 1.7}, {2.9, 2.4, 2.0}, {3.5, 2.9, 2.4}, {4.3, 3.5, 2.9}}
      "Heat out over compressor power in, by outdoor and leaving glycol temperature";
    parameter Real PHeatPumpStandby(unit = "W") = 20;
    parameter Real PControlBoxStandby(unit = "W") = 10;
    parameter Real PPrimaryPump(unit = "W") = 80;
    parameter Real PPumpNominal(unit = "W") = 60 "Either water pump at full speed";

    parameter Real CEmitter(unit = "J/K") = 45e3 "Water and metal of one zone's emitters";
    parameter Real UAEmitter(unit = "W/K") = 100 "One zone's emitters to its room";
    parameter Real CZone(unit = "J/K") = 4e6 "Air and fabric of one zone as a single lump";
    parameter Real UAZone(unit = "W/K") = 71 "One zone to the outdoor air";
    parameter Real TZoneSet(unit = "K") = 293.15 "Thermostat setpoint";
    parameter Real dTZoneDeadband(unit = "K") = 0.6 "Thermostat swing, centred on the setpoint";
    parameter Real PZoneValve(unit = "W") = 10 "Power on a zone's thermostat wire while it calls";

    parameter Real TStartPlant(unit = "K") = 303.15 "Every water and glycol volume at time zero";
    parameter Real TStartZone(unit = "K") = 293.15 "Every zone at time zero";

    RealOutput hpLwt(unit = "K") "Glycol leaving the heat pump"
      annotation(Placement(transformation(origin = {540, 168}, extent = {{-5, -5}, {5, 5}})));
    RealOutput hpEwt(unit = "K") "Glycol entering the heat pump"
      annotation(Placement(transformation(origin = {540, 154}, extent = {{-5, -5}, {5, 5}})));
    RealOutput secondaryLwt(unit = "K") "Water leaving the exchanger"
      annotation(Placement(transformation(origin = {540, 140}, extent = {{-5, -5}, {5, 5}})));
    RealOutput secondaryEwt(unit = "K") "Water entering the exchanger"
      annotation(Placement(transformation(origin = {540, 126}, extent = {{-5, -5}, {5, 5}})));
    RealOutput distSwt(unit = "K") "Water supplied to the house"
      annotation(Placement(transformation(origin = {540, 112}, extent = {{-5, -5}, {5, 5}})));
    RealOutput distRwt(unit = "K") "Water returning from the house"
      annotation(Placement(transformation(origin = {540, 98}, extent = {{-5, -5}, {5, 5}})));
    RealOutput storeHotPipe(unit = "K") "Pipe at the hot tank top"
      annotation(Placement(transformation(origin = {540, 84}, extent = {{-5, -5}, {5, 5}})));
    RealOutput storeColdPipe(unit = "K") "Pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {540, 70}, extent = {{-5, -5}, {5, 5}})));
    RealOutput tankDepth[3, 3](each unit = "K") "Tank (hot, middle, cold) by depth (top, middle, bottom)"
      annotation(Placement(transformation(origin = {540, 56}, extent = {{-5, -5}, {5, 5}})));
    RealOutput primaryFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 42}, extent = {{-5, -5}, {5, 5}})));
    RealOutput secondaryFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 28}, extent = {{-5, -5}, {5, 5}})));
    RealOutput distFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 14}, extent = {{-5, -5}, {5, 5}})));
    RealOutput storeFlow(unit = "m3/s") "Magnitude only: the meter does not tell charge from discharge"
      annotation(Placement(transformation(origin = {540, 0}, extent = {{-5, -5}, {5, 5}})));
    RealOutput hpOduPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -14}, extent = {{-5, -5}, {5, 5}})));
    RealOutput hpCtrlBoxPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -28}, extent = {{-5, -5}, {5, 5}})));
    RealOutput distPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -42}, extent = {{-5, -5}, {5, 5}})));
    RealOutput secondaryPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -56}, extent = {{-5, -5}, {5, 5}})));
    RealOutput zoneTemperature[nZones](each unit = "K")
      annotation(Placement(transformation(origin = {540, -70}, extent = {{-5, -5}, {5, 5}})));
    RealOutput zoneCallPower[nZones](each unit = "W") "Power on each zone's thermostat wire"
      annotation(Placement(transformation(origin = {540, -84}, extent = {{-5, -5}, {5, 5}})));
    RealOutput heatPumpHeat(unit = "W") "Heat the heat pump is putting into the glycol"
      annotation(Placement(transformation(origin = {540, -98}, extent = {{-5, -5}, {5, 5}})));
    RealOutput storeCharge(unit = "m3/s") "Store flow signed: positive into a tank top"
      annotation(Placement(transformation(origin = {540, -112}, extent = {{-5, -5}, {5, 5}})));
    RealOutput thermalEnergy(unit = "J") "Heat held by every volume and zone, above 0 degC"
      annotation(Placement(transformation(origin = {540, -126}, extent = {{-5, -5}, {5, 5}})));
    RealOutput heatPumpEnergy(unit = "J") "Heat delivered by the heat pump since time zero"
      annotation(Placement(transformation(origin = {540, -140}, extent = {{-5, -5}, {5, 5}})));
    RealOutput lossEnergy(unit = "J") "Heat lost to the room and the outdoor air since time zero"
      annotation(Placement(transformation(origin = {540, -154}, extent = {{-5, -5}, {5, 5}})));

    HeatPump heatPump(c = cGlycol, VFlowNominal = VFlowPrimaryNominal, C = CHeatPump, UA = UAHeatPump, TLwtMax = TLwtMax, dTLwtRestart = dTLwtRestart, TOutdoorGrid = TOutdoorGrid, TLwtGrid = TLwtGrid, QTable = QHeatPumpTable, COPTable = COPTable, PStandby = PHeatPumpStandby, PControlBoxStandby = PControlBoxStandby, PPump = PPrimaryPump, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-300, 0}, extent = {{-30, -40}, {30, 40}})));
    Pipe glycolSupply(c = cGlycol) "Heat pump to the exchanger"
      annotation(Placement(transformation(origin = {-225, 30}, extent = {{-10, -10}, {10, 10}})));
    PlateExchanger exchanger(cGlycol = cGlycol, cWater = cWater, UA = UAExchanger, UAStatic = UAExchangerStatic, CSide = CExchangerSide, UALoss = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-160, 0}, extent = {{-20, -40}, {20, 40}})));
    Pipe glycolReturn(c = cGlycol) "Exchanger to the volumizer"
      annotation(Placement(transformation(origin = {-205, -30}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Volume volumizer(C = cGlycol * VVolumizer, UA = UAVolumizer, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-240, -30}, extent = {{-10, -10}, {10, 10}})));
    Expansion glycolExpansion
      annotation(Placement(transformation(origin = {-260, -60}, extent = {{-10, -10}, {10, 10}})));
    Pump secondaryPump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal) "Pump 2, return header to the exchanger"
      annotation(Placement(transformation(origin = {-110, -30}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Valve v1(c = cWater, dpNominal = dpSecondaryNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Exchanger to the supply header"
      annotation(Placement(transformation(origin = {-110, 30}, extent = {{-10, -10}, {10, 10}})));
    Volume supplyHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-60, 140}, extent = {{-10, -10}, {10, 10}})));
    Volume returnHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-60, -140}, extent = {{-10, -10}, {10, 10}})));
    Expansion waterExpansion
      annotation(Placement(transformation(origin = {-100, -110}, extent = {{-10, -10}, {10, 10}})));
    Valve v2(c = cWater, dpNominal = dpStoreHotNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Supply header to the hot tank top"
      annotation(Placement(transformation(origin = {20, 120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Volume hotPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the hot tank top"
      annotation(Placement(transformation(origin = {20, 90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Pipe hotPipeToTank(c = cWater)
      annotation(Placement(transformation(origin = {20, 60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Tank hotTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {20, 0}, extent = {{-15, -40}, {15, 40}})));
    Pipe hotToMiddle(c = cWater) "Hot tank bottom to the middle tank top"
      annotation(Placement(transformation(origin = {50, 0}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Tank middleTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {80, 0}, extent = {{-15, -40}, {15, 40}})));
    Pipe middleToJunction(c = cWater)
      annotation(Placement(transformation(origin = {120, -10}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Volume junction(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Middle tank bottom and cold tank top"
      annotation(Placement(transformation(origin = {120, 30}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Pipe midPipeToJunction(c = cWater)
      annotation(Placement(transformation(origin = {120, 60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Volume midPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Pipe from V3 to the junction"
      annotation(Placement(transformation(origin = {120, 90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Valve v3(c = cWater, dpNominal = dpStoreMidNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Supply header to the cold tank top"
      annotation(Placement(transformation(origin = {120, 120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Pipe junctionToCold(c = cWater)
      annotation(Placement(transformation(origin = {150, 50}, extent = {{-10, -10}, {10, 10}})));
    Tank coldTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {170, 0}, extent = {{-15, -40}, {15, 40}})));
    Pipe coldTankToPipe(c = cWater)
      annotation(Placement(transformation(origin = {170, -60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Volume coldPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {170, -90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Resistance storeReturn(c = cWater, dpNominal = dpStoreColdNominal, VFlowNominal = VFlowNominal) "Junction through the cold tank to the return header, and where the store flow is metered"
      annotation(Placement(transformation(origin = {170, -120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Resistance houseSupply(c = cWater, dpNominal = dpSupplyNominal, VFlowNominal = VFlowNominal) "Supply header to the house supply tee"
      annotation(Placement(transformation(origin = {210, 140}, extent = {{-10, -10}, {10, 10}})));
    Volume distSupply(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe supplying the house"
      annotation(Placement(transformation(origin = {240, 140}, extent = {{-10, -10}, {10, 10}})));
    Pipe distSupplyToTee(c = cWater)
      annotation(Placement(transformation(origin = {270, 140}, extent = {{-10, -10}, {10, 10}})));
    Volume houseSupplyTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {300, 140}, extent = {{-10, -10}, {10, 10}})));
    ZonedDistribution zones(nZones = nZones, c = cWater, dpZoneNominal = dpZoneNominal, VFlowZoneNominal = VFlowZoneNominal, leakage = leakage, dpPumpShutoff = dpPumpShutoff, VFlowPumpMax = VFlowPumpMax, PPumpNominal = PPumpNominal, CEmitter = CEmitter, UAEmitter = UAEmitter, CZone = CZone, UAZone = UAZone, TZoneSet = TZoneSet, dTZoneDeadband = dTZoneDeadband, PZoneValve = PZoneValve, TStartEmitter = TStartPlant, TStartZone = TStartZone)
      annotation(Placement(transformation(origin = {390, 0}, extent = {{-40, -40}, {40, 40}})));
    Volume houseReturnTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Downstream of the circulator"
      annotation(Placement(transformation(origin = {300, -140}, extent = {{-10, -10}, {10, 10}})));
    Pipe teeToDistReturn(c = cWater)
      annotation(Placement(transformation(origin = {270, -140}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Volume distReturn(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe returning from the house"
      annotation(Placement(transformation(origin = {240, -140}, extent = {{-10, -10}, {10, 10}})));
    Valve v4(c = cWater, dpNominal = dpReturnNominal, VFlowNominal = VFlowNominal, leakage = leakage) "House return to the return header, and where the distribution flow is metered"
      annotation(Placement(transformation(origin = {210, -140}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Valve v5(c = cWater, dpNominal = dpBoilerNominal, VFlowNominal = VFlowNominal, leakage = leakage) "House return to the boiler"
      annotation(Placement(transformation(origin = {450, -100}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Volume boiler(C = CBoiler, UA = UABoiler, TSurroundings = TAmbient, TStart = TStartPlant) "The boiler as the water and iron on its branch: it does not fire"
      annotation(Placement(transformation(origin = {450, -40}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Pipe boilerToSupply(c = cWater)
      annotation(Placement(transformation(origin = {450, 60}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));

  protected
    parameter Real cWater(unit = "J/(m3.K)") = rhoWater * cpWater;
    parameter Real cGlycol(unit = "J/(m3.K)") = rhoGlycol * cpGlycol;
    Real EHeatPump(unit = "J", start = 0, fixed = true);
    Real ELoss(unit = "J", start = 0, fixed = true);

  equation
    connect(heatPump.outlet, glycolSupply.port_a)
      annotation(Line(points = {{-270, 30}, {-235, 30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(glycolSupply.port_b, exchanger.glycol_a)
      annotation(Line(points = {{-215, 30}, {-180, 30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(exchanger.glycol_b, glycolReturn.port_a)
      annotation(Line(points = {{-180, -30}, {-195, -30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(glycolReturn.port_b, volumizer.port_b)
      annotation(Line(points = {{-215, -30}, {-230, -30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(volumizer.port_a, heatPump.inlet)
      annotation(Line(points = {{-250, -30}, {-270, -30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(glycolExpansion.port, volumizer.port_a)
      annotation(Line(points = {{-260, -50}, {-260, -30}, {-250, -30}}, color = {160, 60, 160}, thickness = 0.5));
    connect(returnHeader.port_a, secondaryPump.port_a)
      annotation(Line(points = {{-70, -140}, {-80, -140}, {-80, -30}, {-100, -30}}, color = {0, 90, 180}, thickness = 0.5));
    connect(secondaryPump.port_b, exchanger.water_a)
      annotation(Line(points = {{-120, -30}, {-140, -30}}, color = {0, 90, 180}, thickness = 0.5));
    connect(exchanger.water_b, v1.port_a)
      annotation(Line(points = {{-140, 30}, {-120, 30}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v1.port_b, supplyHeader.port_a)
      annotation(Line(points = {{-100, 30}, {-80, 30}, {-80, 140}, {-70, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(waterExpansion.port, returnHeader.port_a)
      annotation(Line(points = {{-100, -100}, {-100, -90}, {-80, -90}, {-80, -140}, {-70, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(supplyHeader.port_b, v2.port_a)
      annotation(Line(points = {{-50, 140}, {20, 140}, {20, 130}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v2.port_b, hotPipe.port_a)
      annotation(Line(points = {{20, 110}, {20, 100}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotPipe.port_b, hotPipeToTank.port_a)
      annotation(Line(points = {{20, 80}, {20, 70}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotPipeToTank.port_b, hotTank.top)
      annotation(Line(points = {{20, 50}, {20, 40}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotTank.bottom, hotToMiddle.port_a)
      annotation(Line(points = {{20, -40}, {20, -50}, {50, -50}, {50, -10}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotToMiddle.port_b, middleTank.top)
      annotation(Line(points = {{50, 10}, {50, 50}, {80, 50}, {80, 40}}, color = {0, 90, 180}, thickness = 0.5));
    connect(middleTank.bottom, middleToJunction.port_a)
      annotation(Line(points = {{80, -40}, {80, -50}, {120, -50}, {120, -20}}, color = {0, 90, 180}, thickness = 0.5));
    connect(middleToJunction.port_b, junction.port_b)
      annotation(Line(points = {{120, 0}, {120, 20}}, color = {0, 90, 180}, thickness = 0.5));
    connect(supplyHeader.port_b, v3.port_a)
      annotation(Line(points = {{-50, 140}, {120, 140}, {120, 130}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v3.port_b, midPipe.port_a)
      annotation(Line(points = {{120, 110}, {120, 100}}, color = {0, 90, 180}, thickness = 0.5));
    connect(midPipe.port_b, midPipeToJunction.port_a)
      annotation(Line(points = {{120, 80}, {120, 70}}, color = {0, 90, 180}, thickness = 0.5));
    connect(midPipeToJunction.port_b, junction.port_a)
      annotation(Line(points = {{120, 50}, {120, 40}}, color = {0, 90, 180}, thickness = 0.5));
    connect(junction.port_a, junctionToCold.port_a)
      annotation(Line(points = {{120, 40}, {130, 40}, {130, 50}, {140, 50}}, color = {0, 90, 180}, thickness = 0.5));
    connect(junctionToCold.port_b, coldTank.top)
      annotation(Line(points = {{160, 50}, {170, 50}, {170, 40}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldTank.bottom, coldTankToPipe.port_a)
      annotation(Line(points = {{170, -40}, {170, -50}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldTankToPipe.port_b, coldPipe.port_a)
      annotation(Line(points = {{170, -70}, {170, -80}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldPipe.port_b, storeReturn.port_a)
      annotation(Line(points = {{170, -100}, {170, -110}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storeReturn.port_b, returnHeader.port_b)
      annotation(Line(points = {{170, -130}, {170, -140}, {-50, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(supplyHeader.port_b, houseSupply.port_a)
      annotation(Line(points = {{-50, 140}, {200, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(houseSupply.port_b, distSupply.port_a)
      annotation(Line(points = {{220, 140}, {230, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distSupply.port_b, distSupplyToTee.port_a)
      annotation(Line(points = {{250, 140}, {260, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distSupplyToTee.port_b, houseSupplyTee.port_a)
      annotation(Line(points = {{280, 140}, {290, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(houseSupplyTee.port_b, zones.supply)
      annotation(Line(points = {{310, 140}, {390, 140}, {390, 40}}, color = {0, 90, 180}, thickness = 0.5));
    connect(zones.ret, houseReturnTee.port_b)
      annotation(Line(points = {{390, -40}, {390, -140}, {310, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(houseReturnTee.port_a, teeToDistReturn.port_a)
      annotation(Line(points = {{290, -140}, {280, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(teeToDistReturn.port_b, distReturn.port_b)
      annotation(Line(points = {{260, -140}, {250, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distReturn.port_a, v4.port_a)
      annotation(Line(points = {{230, -140}, {220, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v4.port_b, returnHeader.port_b)
      annotation(Line(points = {{200, -140}, {-50, -140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(houseReturnTee.port_b, v5.port_a)
      annotation(Line(points = {{310, -140}, {450, -140}, {450, -110}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v5.port_b, boiler.port_a)
      annotation(Line(points = {{450, -90}, {450, -50}}, color = {0, 90, 180}, thickness = 0.5));
    connect(boiler.port_b, boilerToSupply.port_a)
      annotation(Line(points = {{450, -30}, {450, 50}}, color = {0, 90, 180}, thickness = 0.5));
    connect(boilerToSupply.port_b, houseSupplyTee.port_b)
      annotation(Line(points = {{450, 70}, {450, 140}, {310, 140}}, color = {0, 90, 180}, thickness = 0.5));
    connect(v1Position, v1.position)
      annotation(Line(points = {{-110, 62}, {-110, 40}}, color = {0, 0, 127}));
    connect(v2Position, v2.position)
      annotation(Line(points = {{52, 120}, {30, 120}}, color = {0, 0, 127}));
    connect(v3Position, v3.position)
      annotation(Line(points = {{152, 120}, {130, 120}}, color = {0, 0, 127}));
    connect(v4Position, v4.position)
      annotation(Line(points = {{210, -172}, {210, -150}}, color = {0, 0, 127}));
    connect(v5Position, v5.position)
      annotation(Line(points = {{418, -100}, {440, -100}}, color = {0, 0, 127}));
    connect(secondaryPumpOn, secondaryPump.on)
      annotation(Line(points = {{-104, -62}, {-104, -40}}, color = {0, 0, 127}));
    connect(secondaryPumpSpeed, secondaryPump.speed)
      annotation(Line(points = {{-116, -62}, {-116, -40}}, color = {0, 0, 127}));
    connect(distPumpSpeed, zones.speed)
      annotation(Line(points = {{318, 20}, {350, 20}}, color = {0, 0, 127}));
    connect(hpEnable, heatPump.call)
      annotation(Line(points = {{-362, 20}, {-330, 20}}, color = {0, 0, 127}));
    connect(hpScadaControl, heatPump.scadaControl)
      annotation(Line(points = {{-362, -20}, {-330, -20}}, color = {0, 0, 127}));
    connect(TOutdoor, heatPump.TOutdoor)
      annotation(Line(points = {{-362, 170}, {-300, 170}, {-300, 40}}, color = {0, 0, 127}));
    connect(TOutdoor, zones.TOutdoor)
      annotation(Line(points = {{-362, 170}, {335, 170}, {335, -20}, {350, -20}}, color = {0, 0, 127}));

    hpLwt = heatPump.T;
    hpEwt = volumizer.T;
    secondaryLwt = exchanger.TWater;
    secondaryEwt = returnHeader.T;
    distSwt = distSupply.T;
    distRwt = distReturn.T;
    storeHotPipe = hotPipe.T;
    storeColdPipe = coldPipe.T;
    tankDepth[1, :] = hotTank.TSensor;
    tankDepth[2, :] = middleTank.TSensor;
    tankDepth[3, :] = coldTank.TSensor;
    primaryFlow = heatPump.q;
    secondaryFlow = meterReading(v1.q, VFlowMeterMin);
    distFlow = meterReading(v4.q, VFlowMeterMin);
    storeFlow = meterReading(storeReturn.q, VFlowMeterMin);
    hpOduPower = heatPump.oduPower;
    hpCtrlBoxPower = heatPump.ctrlBoxPower;
    distPumpPower = zones.pumpPower;
    secondaryPumpPower = secondaryPump.power;
    zoneTemperature = zones.TZone;
    zoneCallPower = zones.callPower;
    heatPumpHeat = heatPump.Q;
    storeCharge = storeReturn.q;

    der(EHeatPump) = heatPump.Q;
    der(ELoss) = heatPump.QLoss + exchanger.QLoss + volumizer.QLoss + supplyHeader.QLoss + returnHeader.QLoss
      + hotPipe.QLoss + midPipe.QLoss + junction.QLoss + coldPipe.QLoss + hotTank.QLoss + middleTank.QLoss
      + coldTank.QLoss + distSupply.QLoss + houseSupplyTee.QLoss + houseReturnTee.QLoss + distReturn.QLoss
      + boiler.QLoss + zones.QLoss;
    thermalEnergy = heatPump.E + exchanger.E + volumizer.E + supplyHeader.E + returnHeader.E
      + hotPipe.E + midPipe.E + junction.E + coldPipe.E + hotTank.E + middleTank.E
      + coldTank.E + distSupply.E + houseSupplyTee.E + houseReturnTee.E + distReturn.E
      + boiler.E + zones.E;
    heatPumpEnergy = EHeatPump;
    lossEnergy = ELoss;
    annotation(
      experiment(StartTime = 0, StopTime = 86400, Tolerance = 1e-6, Interval = 60),
      Diagram(coordinateSystem(extent = {{-380, -190}, {560, 190}}, preserveAspectRatio = true)),
      Icon(graphics = {
        Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
        Text(extent = {{-90, 30}, {90, -30}}, textString = "%name", textColor = {0, 0, 0})}),
      Documentation(info = "<html><p>The plant's pipework. A filled port is a body of fluid and a hollow port is an end of a pipe, valve, resistance or pump: every joint has exactly one filled port, so between two bodies of fluid there is always one part that carries the flow.</p></html>"));
  end Plant;
end KatahdinComponents;
