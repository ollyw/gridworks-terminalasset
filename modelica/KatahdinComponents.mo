package KatahdinComponents
  "The Katahdin heating plant as connected components: the inputs, outputs and parameters of Katahdin.Plant, drawn as its pipework with the parts of Hydronic"

  model Plant
    "Valve positions, pump commands and weather in; every sensed temperature, flow and power out"

    constant Integer nZones = 4 "Zones on the distribution loop";
    constant Integer nSeg = 9 "Layers in each store tank";
    constant Integer sensorCell[3] = {2, 5, 8} "Layer read by each depth sensor of a tank, top first";

    Hydronic.RealInput v1Position(start = 0) "V1, exchanger to supply header: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {-110, 62}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput v2Position(start = 1) "V2, supply header to hot tank top: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {52, 120}, extent = {{-5, -5}, {5, 5}}, rotation = 180)));
    Hydronic.RealInput v3Position(start = 0) "V3, supply header to cold tank top: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {152, 120}, extent = {{-5, -5}, {5, 5}}, rotation = 180)));
    Hydronic.RealInput v4Position(start = 0) "V4, house return to return header: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {210, -172}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput v5Position(start = 0) "V5, house return to boiler: 0 closed, 1 open"
      annotation(Placement(transformation(origin = {418, -100}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput secondaryPumpOn(start = 0) "Pump 2 relay: 0 off, 1 on"
      annotation(Placement(transformation(origin = {-104, -62}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput secondaryPumpSpeed(start = 1) "Pump 2 speed as a fraction of full"
      annotation(Placement(transformation(origin = {-116, -62}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput distPumpSpeed(start = 1) "Distribution circulator speed as a fraction of full"
      annotation(Placement(transformation(origin = {318, 20}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput hpEnable(start = 0) "The scada's call for the heat pump: 0 no call, 1 call"
      annotation(Placement(transformation(origin = {-362, 20}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput hpScadaControl(start = 1) "Who holds the heat pump's call: 0 its aquastat, which makes none here, 1 the scada"
      annotation(Placement(transformation(origin = {-362, -20}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput TOutdoor(unit = "K", start = 268.15) "Outdoor air temperature"
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

    Hydronic.RealOutput hpLwt(unit = "K") "Glycol leaving the heat pump"
      annotation(Placement(transformation(origin = {540, 168}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpEwt(unit = "K") "Glycol entering the heat pump"
      annotation(Placement(transformation(origin = {540, 154}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput secondaryLwt(unit = "K") "Water leaving the exchanger"
      annotation(Placement(transformation(origin = {540, 140}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput secondaryEwt(unit = "K") "Water entering the exchanger"
      annotation(Placement(transformation(origin = {540, 126}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distSwt(unit = "K") "Water supplied to the house"
      annotation(Placement(transformation(origin = {540, 112}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distRwt(unit = "K") "Water returning from the house"
      annotation(Placement(transformation(origin = {540, 98}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeHotPipe(unit = "K") "Pipe at the hot tank top"
      annotation(Placement(transformation(origin = {540, 84}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeColdPipe(unit = "K") "Pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {540, 70}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput tankDepth[3, 3](each unit = "K") "Tank (hot, middle, cold) by depth (top, middle, bottom)"
      annotation(Placement(transformation(origin = {540, 56}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput primaryFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 42}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput secondaryFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 28}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {540, 14}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeFlow(unit = "m3/s") "Magnitude only: the meter does not tell charge from discharge"
      annotation(Placement(transformation(origin = {540, 0}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpOduPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -14}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpCtrlBoxPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -28}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -42}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput secondaryPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {540, -56}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput zoneTemperature[nZones](each unit = "K")
      annotation(Placement(transformation(origin = {540, -70}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput zoneCallPower[nZones](each unit = "W") "Power on each zone's thermostat wire"
      annotation(Placement(transformation(origin = {540, -84}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput heatPumpHeat(unit = "W") "Heat the heat pump is putting into the glycol"
      annotation(Placement(transformation(origin = {540, -98}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeCharge(unit = "m3/s") "Store flow signed: positive into a tank top"
      annotation(Placement(transformation(origin = {540, -112}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput thermalEnergy(unit = "J") "Heat held by every volume and zone, above 0 degC"
      annotation(Placement(transformation(origin = {540, -126}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput heatPumpEnergy(unit = "J") "Heat delivered by the heat pump since time zero"
      annotation(Placement(transformation(origin = {540, -140}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput lossEnergy(unit = "J") "Heat lost to the room and the outdoor air since time zero"
      annotation(Placement(transformation(origin = {540, -154}, extent = {{-5, -5}, {5, 5}})));

    Hydronic.HeatPump heatPump(c = cGlycol, VFlowNominal = VFlowPrimaryNominal, C = CHeatPump, UA = UAHeatPump, TLwtMax = TLwtMax, dTLwtRestart = dTLwtRestart, TOutdoorGrid = TOutdoorGrid, TLwtGrid = TLwtGrid, QTable = QHeatPumpTable, COPTable = COPTable, PStandby = PHeatPumpStandby, PControlBoxStandby = PControlBoxStandby, PPump = PPrimaryPump, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-300, 0}, extent = {{-30, -40}, {30, 40}})));
    Hydronic.Pipe glycolSupply(c = cGlycol) "Heat pump to the exchanger"
      annotation(Placement(transformation(origin = {-225, 30}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.PlateExchanger exchanger(cGlycol = cGlycol, cWater = cWater, UA = UAExchanger, UAStatic = UAExchangerStatic, CSide = CExchangerSide, UALoss = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-160, 0}, extent = {{-20, -40}, {20, 40}})));
    Hydronic.Pipe glycolReturn(c = cGlycol) "Exchanger to the volumizer"
      annotation(Placement(transformation(origin = {-205, -30}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Hydronic.Volume volumizer(C = cGlycol * VVolumizer, UA = UAVolumizer, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-240, -30}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Expansion glycolExpansion
      annotation(Placement(transformation(origin = {-260, -60}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Pump secondaryPump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal) "Pump 2, return header to the exchanger"
      annotation(Placement(transformation(origin = {-110, -30}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Hydronic.Valve v1(c = cWater, dpNominal = dpSecondaryNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Exchanger to the supply header"
      annotation(Placement(transformation(origin = {-110, 30}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Volume supplyHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-60, 140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Volume returnHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {-60, -140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Expansion waterExpansion
      annotation(Placement(transformation(origin = {-100, -110}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Valve v2(c = cWater, dpNominal = dpStoreHotNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Supply header to the hot tank top"
      annotation(Placement(transformation(origin = {20, 120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Volume hotPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the hot tank top"
      annotation(Placement(transformation(origin = {20, 90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Pipe hotPipeToTank(c = cWater)
      annotation(Placement(transformation(origin = {20, 60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Tank hotTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {20, 0}, extent = {{-15, -40}, {15, 40}})));
    Hydronic.Pipe hotToMiddle(c = cWater) "Hot tank bottom to the middle tank top"
      annotation(Placement(transformation(origin = {50, 0}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Hydronic.Tank middleTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {80, 0}, extent = {{-15, -40}, {15, 40}})));
    Hydronic.Pipe middleToJunction(c = cWater)
      annotation(Placement(transformation(origin = {120, -10}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Hydronic.Volume junction(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Middle tank bottom and cold tank top"
      annotation(Placement(transformation(origin = {120, 30}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Pipe midPipeToJunction(c = cWater)
      annotation(Placement(transformation(origin = {120, 60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Volume midPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Pipe from V3 to the junction"
      annotation(Placement(transformation(origin = {120, 90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Valve v3(c = cWater, dpNominal = dpStoreMidNominal, VFlowNominal = VFlowNominal, leakage = leakage) "Supply header to the cold tank top"
      annotation(Placement(transformation(origin = {120, 120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Pipe junctionToCold(c = cWater)
      annotation(Placement(transformation(origin = {150, 50}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Tank coldTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {170, 0}, extent = {{-15, -40}, {15, 40}})));
    Hydronic.Pipe coldTankToPipe(c = cWater)
      annotation(Placement(transformation(origin = {170, -60}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Volume coldPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {170, -90}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Resistance storeReturn(c = cWater, dpNominal = dpStoreColdNominal, VFlowNominal = VFlowNominal) "Junction through the cold tank to the return header, and where the store flow is metered"
      annotation(Placement(transformation(origin = {170, -120}, extent = {{-10, -10}, {10, 10}}, rotation = -90)));
    Hydronic.Resistance houseSupply(c = cWater, dpNominal = dpSupplyNominal, VFlowNominal = VFlowNominal) "Supply header to the house supply tee"
      annotation(Placement(transformation(origin = {210, 140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Volume distSupply(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe supplying the house"
      annotation(Placement(transformation(origin = {240, 140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Pipe distSupplyToTee(c = cWater)
      annotation(Placement(transformation(origin = {270, 140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Volume houseSupplyTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {300, 140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.ZonedDistribution zones(nZones = nZones, c = cWater, dpZoneNominal = dpZoneNominal, VFlowZoneNominal = VFlowZoneNominal, leakage = leakage, dpPumpShutoff = dpPumpShutoff, VFlowPumpMax = VFlowPumpMax, PPumpNominal = PPumpNominal, CEmitter = CEmitter, UAEmitter = UAEmitter, CZone = CZone, UAZone = UAZone, TZoneSet = TZoneSet, dTZoneDeadband = dTZoneDeadband, PZoneValve = PZoneValve, TStartEmitter = TStartPlant, TStartZone = TStartZone)
      annotation(Placement(transformation(origin = {390, 0}, extent = {{-40, -40}, {40, 40}})));
    Hydronic.Volume houseReturnTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Downstream of the circulator"
      annotation(Placement(transformation(origin = {300, -140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Pipe teeToDistReturn(c = cWater)
      annotation(Placement(transformation(origin = {270, -140}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Hydronic.Volume distReturn(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe returning from the house"
      annotation(Placement(transformation(origin = {240, -140}, extent = {{-10, -10}, {10, 10}})));
    Hydronic.Valve v4(c = cWater, dpNominal = dpReturnNominal, VFlowNominal = VFlowNominal, leakage = leakage) "House return to the return header, and where the distribution flow is metered"
      annotation(Placement(transformation(origin = {210, -140}, extent = {{-10, -10}, {10, 10}}, rotation = 180)));
    Hydronic.Valve v5(c = cWater, dpNominal = dpBoilerNominal, VFlowNominal = VFlowNominal, leakage = leakage) "House return to the boiler"
      annotation(Placement(transformation(origin = {450, -100}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Hydronic.Volume boiler(C = CBoiler, UA = UABoiler, TSurroundings = TAmbient, TStart = TStartPlant) "The boiler as the water and iron on its branch: it does not fire"
      annotation(Placement(transformation(origin = {450, -40}, extent = {{-10, -10}, {10, 10}}, rotation = 90)));
    Hydronic.Pipe boilerToSupply(c = cWater)
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
    secondaryFlow = Hydronic.meterReading(v1.q, VFlowMeterMin);
    distFlow = Hydronic.meterReading(v4.q, VFlowMeterMin);
    storeFlow = Hydronic.meterReading(storeReturn.q, VFlowMeterMin);
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
      Documentation(info = "<html><p>The plant's pipework, built of the parts in Hydronic.</p></html>"));
  end Plant;
end KatahdinComponents;
