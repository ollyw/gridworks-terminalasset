package Beech
  "The Beech heating plant as connected components, each placed where the plant's schematic draws it, with the parts of Hydronic"

  model Plant
    "Relays, pump speeds and weather in; every sensed temperature, flow and power out"

    constant Integer nZones = 2 "Zones on the distribution loop: down, up";
    constant Integer nSeg = 9 "Layers in the buffer and in each store tank";
    constant Integer sensorCell[3] = {2, 5, 8} "Layer read by each depth sensor of a tank, top first";

    Hydronic.RealInput hpEnable(start = 0) "The scada's call for the heat pump: 0 no call, 1 call"
      annotation(Placement(transformation(origin = {1365, -112.5}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput hpScadaControl(start = 1) "Who holds the heat pump's call: 0 its aquastat, which makes none here, 1 the scada"
      annotation(Placement(transformation(origin = {1387.5, -112.5}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput TOutdoor(unit = "K", start = 268.15) "Outdoor air temperature"
      annotation(Placement(transformation(origin = {1410, -112.5}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput primaryPumpOn(start = 0) "Primary pump: 0 off, 1 on"
      annotation(Placement(transformation(origin = {1173.3, -210}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput primaryPumpSpeed(start = 1) "Primary pump speed as a fraction of full"
      annotation(Placement(transformation(origin = {1187.7, -210}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput siegMotorOn(start = 0) "Siegenthaler valve motor: 0 stopped, 1 running"
      annotation(Placement(transformation(origin = {1081.5, -18}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput siegTowardKeep(start = 0) "Which way the Siegenthaler valve motor runs: 0 toward send, 1 toward keep"
      annotation(Placement(transformation(origin = {1060.5, -18}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput chargeDischarge(start = 0) "The store relay: 0 discharge, with the ISO valve open; 1 charge, with the ISO valve closed"
      annotation(Placement(transformation(origin = {754.5, -33}, extent = {{-5, -5}, {5, 5}}, rotation = -90)));
    Hydronic.RealInput storePumpOn(start = 0) "Store pump: 0 off, 1 on"
      annotation(Placement(transformation(origin = {750, -349.2}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput storePumpSpeed(start = 1) "Store pump speed as a fraction of full"
      annotation(Placement(transformation(origin = {750, -334.8}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealInput distPumpSpeed(start = 1) "Distribution pump speed as a fraction of full"
      annotation(Placement(transformation(origin = {532.8, -780}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput zoneScadaControl[nZones](each start = 0) "Who holds each zone's call: 0 its thermostat, 1 the scada"
      annotation(Placement(transformation(origin = {354, -870}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput zoneScadaCall[nZones](each start = 0) "The scada's call for each zone: 0 no call, 1 call"
      annotation(Placement(transformation(origin = {378, -870}, extent = {{-5, -5}, {5, 5}}, rotation = 90)));
    Hydronic.RealInput boilerCall(start = 0) "The boiler: 0 not called, 1 called, when its pump runs and its burner holds its aquastat setting"
      annotation(Placement(transformation(origin = {120, -277.5}, extent = {{-5, -5}, {5, 5}})));

    parameter Real rhoWater(unit = "kg/m3") = 990;
    parameter Real cpWater(unit = "J/(kg.K)") = 4180;

    parameter Real VFlowNominal(unit = "m3/s") = 3.155e-4 "Flow at which the branch pressure drops are given: 5 US gpm";
    parameter Real VFlowZoneNominal(unit = "m3/s") = 1.577e-4 "Flow at which dpZoneNominal is given: 2.5 US gpm";
    parameter Real dpPumpShutoff(unit = "Pa") = 40e3 "Head of each pump at full speed and no flow";
    parameter Real VFlowPumpMax(unit = "m3/s") = 6.31e-4 "Flow of each pump at full speed and no head";
    parameter Real dpPumpCheckNominal(unit = "Pa") = 1.0e3 "The check valve in a pump's flange, beyond its cracking pressure";
    parameter Real dpCrack(unit = "Pa") = 1.5e3 "Pressure across a check valve at which it opens";
    parameter Real dpHeatPumpNominal(unit = "Pa") = 6.0e3 "The heat pump's water side and its check valve, beyond the cracking pressure";
    parameter Real dpHeatPumpReturnNominal(unit = "Pa") = 1.0e3 "Cold header to the Siegenthaler tee";
    parameter Real dpSiegSendNominal(unit = "Pa") = 4.0e3 "Siegenthaler valve, fully sending, to the hot header";
    parameter Real dpSiegKeepNominal(unit = "Pa") = 4.0e3 "Siegenthaler valve, fully keeping, to the Siegenthaler tee";
    parameter Real dpIsoNominal(unit = "Pa") = 2.0e3 "Hot header through the ISO valve to the buffer top";
    parameter Real dpStoreHotNominal(unit = "Pa") = 1.0e3 "Hot header to the hot tank top";
    parameter Real dpStoreColdNominal(unit = "Pa") = 1.0e3 "Cold tank bottom to the charge/discharge valve";
    parameter Real dpChargeNominal(unit = "Pa") = 2.0e3 "Charge/discharge valve, at charge, to the cold header";
    parameter Real dpDischargeNominal(unit = "Pa") = 2.0e3 "Charge/discharge valve, at discharge, to the store pump";
    parameter Real dpBoilerNominal(unit = "Pa") = 3.0e3 "The boiler's branch and its check valve, beyond the cracking pressure";
    parameter Real dpZoneNominal(unit = "Pa") = 18.5e3 "One zone's valve and emitter at VFlowZoneNominal";
    parameter Real leakage = 1e-6 "Conductance of a closed valve as a fraction of its open conductance";
    parameter Real VFlowMeterMin(unit = "m3/s") = 1.26e-5 "Flow below which a flow meter reads zero: 0.2 US gpm";

    parameter Real VTank(unit = "m3") = 0.454 "Volume of one store tank: 120 US gal";
    parameter Real hTank(unit = "m") = 1.6 "Water height of one store tank";
    parameter Real UATank(unit = "W/K") = 2.0 "Loss of one store tank to the room";
    parameter Real VBuffer(unit = "m3") = 0.3;
    parameter Real hBuffer(unit = "m") = 1.5 "Water height of the buffer";
    parameter Real UABuffer(unit = "W/K") = 2.0 "Loss of the buffer to the room";
    parameter Real kTankEffective(unit = "W/(m.K)") = 1.5 "Vertical conduction through water and wall";
    parameter Real tauBuoyancy(unit = "s") = 30 "Time for a layer lying under a colder one to mix with it";
    parameter Real VPipe(unit = "m3") = 1.5e-3 "Water in each header, tee, valve body and sensed pipe run";
    parameter Real UAPipe(unit = "W/K") = 0.5 "Loss of each such run to the room";
    parameter Real TAmbient(unit = "K") = 291.15 "Mechanical room air";

    parameter Real CHeatPump(unit = "J/K") = 30e3 "Water and metal in the indoor unit";
    parameter Real UAHeatPump(unit = "W/K") = 3.0 "Loss of the indoor unit to the room";
    parameter Real VFlowHeatPumpMin(unit = "m3/s") = 6.3e-5 "Water flow below which the compressor does not run: 1 US gpm";
    parameter Real TLwtMax(unit = "K") = 353.15 "Leaving water temperature at which the compressor stops";
    parameter Real dTLwtRestart(unit = "K") = 8 "Fall below TLwtMax at which the compressor may restart";
    parameter Real TOutdoorGrid[4](each unit = "K") = {253.15, 263.15, 273.15, 283.15};
    parameter Real TLwtGrid[4](each unit = "K") = {308.15, 323.15, 338.15, 353.15};
    parameter Real QHeatPumpTable[4, 4](each unit = "W") =
      {{9000, 8500, 8000, 7500}, {11000, 10500, 10000, 9500}, {13000, 12500, 12000, 11500}, {15000, 14500, 14000, 13500}}
      "Heat output by outdoor and leaving water temperature";
    parameter Real COPTable[4, 4] =
      {{2.4, 2.0, 1.7, 1.4}, {2.9, 2.4, 2.0, 1.7}, {3.5, 2.9, 2.4, 2.0}, {4.3, 3.5, 2.9, 2.4}}
      "Heat out over compressor power in, by outdoor and leaving water temperature";
    parameter Real indoorShare = 0.4 "Share of the compressor power drawn by the indoor unit";
    parameter Real PStandbyOutdoor(unit = "W") = 20 "Outdoor unit with the compressors stopped";
    parameter Real PStandbyIndoor(unit = "W") = 10 "Indoor unit with the compressors stopped";
    parameter Real PPumpNominal(unit = "W") = 60 "Each pump at full speed";

    parameter Real siegTravel(unit = "s") = 94 "Siegenthaler valve motor time from the send stop to the keep stop";
    parameter Real siegOnset(unit = "s") = 26 "Motor time from the send stop at which the valve begins to keep";
    parameter Real siegComplete(unit = "s") = 56 "Motor time from the send stop at which the valve keeps all";
    parameter Real siegStart(unit = "s") = 94 "Motor time from the send stop at time zero: at the keep stop";

    parameter Real CBoiler(unit = "J/K") = 233e3 "Water and iron in the boiler";
    parameter Real UABoiler(unit = "W/K") = 5.0;
    parameter Real QBoiler(unit = "W") = 25e3 "Heat the burner puts into the water";
    parameter Real PBoiler(unit = "W") = 250 "Electrical power of the burner while it fires";
    parameter Real TBoilerAquastat(unit = "K") = 355.15 "Boiler water temperature at which the burner stops";
    parameter Real dTBoilerAquastat(unit = "K") = 10 "Fall below TBoilerAquastat at which the burner fires again";

    parameter Real CEmitter(unit = "J/K") = 90e3 "Water and metal of one zone's emitters";
    parameter Real UAEmitter(unit = "W/K") = 200 "One zone's emitters to its room";
    parameter Real CZone(unit = "J/K") = 8e6 "Air and fabric of one zone as a single lump";
    parameter Real UAZone(unit = "W/K") = 140 "One zone to the outdoor air";
    parameter Real TZoneSet(unit = "K") = 293.15 "Thermostat setpoint";
    parameter Real dTZoneDeadband(unit = "K") = 0.6 "Thermostat swing, centred on the setpoint";
    parameter Real PZoneValve(unit = "W") = 10 "Power on a zone's thermostat wire while it calls";

    parameter Real TStartPlant(unit = "K") = 303.15 "Every water volume at time zero";
    parameter Real TStartZone(unit = "K") = 293.15 "Every zone at time zero";

    Hydronic.RealOutput hpLwt(unit = "K") "Water leaving the heat pump"
      annotation(Placement(transformation(origin = {1590, -45}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpEwt(unit = "K") "Water entering the heat pump"
      annotation(Placement(transformation(origin = {1590, -78}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput primaryFlow(unit = "m3/s") "Flow through the heat pump"
      annotation(Placement(transformation(origin = {1590, -111}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput siegFlow(unit = "m3/s") "Flow the Siegenthaler valve keeps"
      annotation(Placement(transformation(origin = {1590, -144}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput siegHot(unit = "K") "Kept water at the Siegenthaler flow meter"
      annotation(Placement(transformation(origin = {1590, -177}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput siegCold(unit = "K") "Water coming to the Siegenthaler tee from the cold pipe"
      annotation(Placement(transformation(origin = {1590, -210}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput siegKeep "Siegenthaler valve: 0 all sent, 1 all kept"
      annotation(Placement(transformation(origin = {1590, -243}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput bufferHotPipe(unit = "K") "Pipe at the buffer top"
      annotation(Placement(transformation(origin = {1590, -276}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput bufferDepth[3](each unit = "K") "Buffer by depth (top, middle, bottom)"
      annotation(Placement(transformation(origin = {1590, -309}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distSwt(unit = "K") "Water supplied to the house"
      annotation(Placement(transformation(origin = {1590, -342}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distRwt(unit = "K") "Water returning from the house"
      annotation(Placement(transformation(origin = {1590, -375}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distFlow(unit = "m3/s")
      annotation(Placement(transformation(origin = {1590, -408}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeHotPipe(unit = "K") "Pipe at the hot tank top"
      annotation(Placement(transformation(origin = {1590, -441}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeColdPipe(unit = "K") "Pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {1590, -474}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeFlow(unit = "m3/s") "Flow on the store pump's branch: the discharge, and nothing while the store charges"
      annotation(Placement(transformation(origin = {1590, -507}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput tankDepth[3, 3](each unit = "K") "Tank (hot, middle, cold) by depth (top, middle, bottom)"
      annotation(Placement(transformation(origin = {1590, -540}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpOduPower(unit = "W")
      annotation(Placement(transformation(origin = {1590, -573}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput hpIduPower(unit = "W")
      annotation(Placement(transformation(origin = {1590, -606}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput primaryPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {1590, -639}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storePumpPower(unit = "W")
      annotation(Placement(transformation(origin = {1590, -672}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput distPumpPower(unit = "W")
      annotation(Placement(transformation(origin = {1590, -705}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput oilBoilerPower(unit = "W") "Burner and boiler pump"
      annotation(Placement(transformation(origin = {1590, -738}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput zoneTemperature[nZones](each unit = "K")
      annotation(Placement(transformation(origin = {1590, -771}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput zoneCallPower[nZones](each unit = "W") "Power on each zone's thermostat wire"
      annotation(Placement(transformation(origin = {1590, -804}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput heatPumpHeat(unit = "W") "Heat the heat pump is putting into the water"
      annotation(Placement(transformation(origin = {1590, -837}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput boilerHeat(unit = "W") "Heat the boiler is putting into the water"
      annotation(Placement(transformation(origin = {1590, -870}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput storeCharge(unit = "m3/s") "Store flow signed: positive into the hot tank top"
      annotation(Placement(transformation(origin = {1590, -903}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput thermalEnergy(unit = "J") "Heat held by every volume and zone, above 0 degC"
      annotation(Placement(transformation(origin = {1590, -936}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput heatPumpEnergy(unit = "J") "Heat delivered by the heat pump since time zero"
      annotation(Placement(transformation(origin = {1590, -969}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput boilerEnergy(unit = "J") "Heat delivered by the boiler since time zero"
      annotation(Placement(transformation(origin = {1590, -1002}, extent = {{-5, -5}, {5, 5}})));
    Hydronic.RealOutput lossEnergy(unit = "J") "Heat lost to the room and the outdoor air since time zero"
      annotation(Placement(transformation(origin = {1590, -1035}, extent = {{-5, -5}, {5, 5}})));

    Hydronic.SplitHeatPump heatPump(C = CHeatPump, UA = UAHeatPump, TSurroundings = TAmbient, VFlowMin = VFlowHeatPumpMin, indoorShare = indoorShare, PStandbyOutdoor = PStandbyOutdoor, PStandbyIndoor = PStandbyIndoor, TLwtMax = TLwtMax, dTLwtRestart = dTLwtRestart, TOutdoorGrid = TOutdoorGrid, TLwtGrid = TLwtGrid, QTable = QHeatPumpTable, COPTable = COPTable, TStart = TStartPlant) "The indoor unit"
      annotation(Placement(transformation(origin = {1387.5, -210}, extent = {{-45, -60}, {45, 60}})));
    Hydronic.CheckValve hpCheck(c = cWater, dpNominal = dpHeatPumpNominal, VFlowNominal = VFlowNominal, dpCrack = dpCrack, leakage = leakage) "The heat pump's water side and the check valve at its outlet"
      annotation(Placement(transformation(origin = {1294.5, -225}, extent = {{-12, -12}, {12, 12}}, rotation = 180)));
    Hydronic.Volume hpSupply(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {1246.5, -192}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.FlowMeter primaryMeter(c = cWater, VFlowMin = VFlowMeterMin)
      annotation(Placement(transformation(origin = {1246.5, -150}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.ThreeWayValve siegValve(c = cWater, C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant, dpRestNominal = dpSiegSendNominal, dpDrivenNominal = dpSiegKeepNominal, VFlowNominal = VFlowNominal, leakage = leakage) "The Siegenthaler valve: at rest all sent to the hot header, driven all kept"
      annotation(Placement(transformation(origin = {1071, -117}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.ValveMotor siegMotor(travel = siegTravel, tOnset = siegOnset, tComplete = siegComplete, tStart = siegStart)
      annotation(Placement(transformation(origin = {1071, -63}, extent = {{-12, -21}, {12, 21}}, rotation = -90)));
    Hydronic.Volume siegKeepPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe of the kept water"
      annotation(Placement(transformation(origin = {1071, -157.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.FlowMeter siegMeter(c = cWater, VFlowMin = VFlowMeterMin)
      annotation(Placement(transformation(origin = {1071, -199.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Volume siegTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Where the kept water joins the return to the heat pump"
      annotation(Placement(transformation(origin = {1071, -237}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Resistance hpReturn(c = cWater, dpNominal = dpHeatPumpReturnNominal, VFlowNominal = VFlowNominal) "Cold header to the Siegenthaler tee"
      annotation(Placement(transformation(origin = {1002, -375}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Pump primaryPump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal)
      annotation(Placement(transformation(origin = {1180.5, -255}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Volume hotHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Where the heat pump, the boiler and the store hot pipe meet, on the far side of the ISO valve from the buffer"
      annotation(Placement(transformation(origin = {885, -193.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Valve isoValve(c = cWater, dpNominal = dpIsoNominal, VFlowNominal = VFlowNominal, leakage = leakage) "The ISO valve, hot header to the buffer"
      annotation(Placement(transformation(origin = {754.5, -193.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Complement isoPosition "The ISO valve is open while the store relay is at discharge"
      annotation(Placement(transformation(origin = {754.5, -147}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Volume bufferHotTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the buffer top, where the distribution supply leaves"
      annotation(Placement(transformation(origin = {699, -220.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Pipe bufferTop(c = cWater)
      annotation(Placement(transformation(origin = {649.5, -193.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Tank buffer(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VBuffer, height = hBuffer, UA = UABuffer, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {594, -322.5}, extent = {{-54, -105}, {54, 105}})));
    Hydronic.Pipe bufferBottom(c = cWater)
      annotation(Placement(transformation(origin = {594, -451.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Volume bufferColdTee(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Where the distribution return meets the buffer bottom"
      annotation(Placement(transformation(origin = {660, -475.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Pipe coldRun(c = cWater)
      annotation(Placement(transformation(origin = {738, -475.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Volume coldHeader(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Where the store pump, the charge/discharge valve and the returns to the heat pump and the boiler leave the cold pipe"
      annotation(Placement(transformation(origin = {885, -475.5}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Pipe distSupply(c = cWater)
      annotation(Placement(transformation(origin = {699, -450}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Volume airSeparator(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe supplying the house"
      annotation(Placement(transformation(origin = {631.5, -741}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Pump distPump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal) "The distribution pump, run while a zone valve is open"
      annotation(Placement(transformation(origin = {540, -741}, extent = {{-12, -12}, {12, 12}}, rotation = 180)));
    Hydronic.Volume supplyManifold(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {477, -741}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Zones zones(nZones = nZones, c = cWater, dpZoneNominal = dpZoneNominal, VFlowZoneNominal = VFlowZoneNominal, leakage = leakage, CEmitter = CEmitter, UAEmitter = UAEmitter, CZone = CZone, UAZone = UAZone, TZoneSet = TZoneSet, dTZoneDeadband = dTZoneDeadband, PZoneValve = PZoneValve, TStartEmitter = TStartPlant, TStartZone = TStartZone)
      annotation(Placement(transformation(origin = {336, -768}, extent = {{-60, -57}, {60, 57}})));
    Hydronic.Volume returnManifold(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe returning from the house"
      annotation(Placement(transformation(origin = {225, -750}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.FlowMeter distMeter(c = cWater, VFlowMin = VFlowMeterMin)
      annotation(Placement(transformation(origin = {345, -645}, extent = {{-12, -12}, {12, 12}})));
    Hydronic.Expansion expansion
      annotation(Placement(transformation(origin = {180, -930}, extent = {{-15, -15}, {15, 15}})));
    Hydronic.Resistance storeHot(c = cWater, dpNominal = dpStoreHotNominal, VFlowNominal = VFlowNominal) "Hot header to the hot tank top"
      annotation(Placement(transformation(origin = {796.5, -145.5}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Volume hotPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the hot tank top"
      annotation(Placement(transformation(origin = {1242, -502.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Pipe hotPipeToTank(c = cWater)
      annotation(Placement(transformation(origin = {1242, -720}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));
    Hydronic.Tank hotTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant) "Tank 1"
      annotation(Placement(transformation(origin = {1098, -1005}, extent = {{-51, -67.5}, {51, 67.5}})));
    Hydronic.Pipe hotToMiddle(c = cWater) "Hot tank bottom to the middle tank top"
      annotation(Placement(transformation(origin = {1188, -840}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Tank middleTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant) "Tank 2"
      annotation(Placement(transformation(origin = {1098, -802.5}, extent = {{-51, -67.5}, {51, 67.5}})));
    Hydronic.Pipe middleToCold(c = cWater) "Middle tank bottom to the cold tank top"
      annotation(Placement(transformation(origin = {1167, -795}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Tank coldTank(nLayers = nSeg, sensorLayer = sensorCell, c = cWater, V = VTank, height = hTank, UA = UATank, kEffective = kTankEffective, tauBuoyancy = tauBuoyancy, TSurroundings = TAmbient, TStart = TStartPlant) "Tank 3"
      annotation(Placement(transformation(origin = {1098, -600}, extent = {{-51, -67.5}, {51, 67.5}})));
    Hydronic.Pipe coldTankToPipe(c = cWater)
      annotation(Placement(transformation(origin = {1209, -630}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Volume coldPipe(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant) "Sensed pipe at the cold tank bottom"
      annotation(Placement(transformation(origin = {1209, -405}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Resistance storeCold(c = cWater, dpNominal = dpStoreColdNominal, VFlowNominal = VFlowNominal) "Cold tank bottom to the charge/discharge valve"
      annotation(Placement(transformation(origin = {1080, -292.5}, extent = {{-12, -12}, {12, 12}}, rotation = 180)));
    Hydronic.ThreeWayValve chargeValve(c = cWater, C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant, dpRestNominal = dpDischargeNominal, dpDrivenNominal = dpChargeNominal, VFlowNominal = VFlowNominal, leakage = leakage) "The charge/discharge valve: at rest the store pump's branch is open to the store, driven the store is open to the cold header"
      annotation(Placement(transformation(origin = {780, -255}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Volume storePumpOutlet(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {780, -300}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.CheckedPump storePump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal, dpCheckNominal = dpPumpCheckNominal, VFlowNominal = VFlowNominal, dpCrack = dpCrack, leakage = leakage) "The store pump and the check valve in its flange"
      annotation(Placement(transformation(origin = {780, -342}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Volume storePumpInlet(C = cWater * VPipe, UA = UAPipe, TSurroundings = TAmbient, TStart = TStartPlant)
      annotation(Placement(transformation(origin = {780, -382.5}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.FlowMeter storeMeter(c = cWater, VFlowMin = VFlowMeterMin) "On the store pump's branch, so it reads the discharge and not the charge"
      annotation(Placement(transformation(origin = {780, -423}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.Boiler boiler(C = CBoiler, UA = UABoiler, TSurroundings = TAmbient, TStart = TStartPlant, QBurner = QBoiler, PBurner = PBoiler, TAquastat = TBoilerAquastat, dTAquastat = dTBoilerAquastat)
      annotation(Placement(transformation(origin = {235.5, -277.5}, extent = {{-60, -67.5}, {60, 67.5}})));
    Hydronic.CheckValve boilerCheck(c = cWater, dpNominal = dpBoilerNominal, VFlowNominal = VFlowNominal, dpCrack = dpCrack, leakage = leakage) "The boiler's branch and the check valve at its outlet"
      annotation(Placement(transformation(origin = {330, -112.5}, extent = {{-12, -12}, {12, 12}}, rotation = 90)));
    Hydronic.CheckedPump boilerPump(c = cWater, dpShutoff = dpPumpShutoff, VFlowMax = VFlowPumpMax, PNominal = PPumpNominal, dpCheckNominal = dpPumpCheckNominal, VFlowNominal = VFlowNominal, dpCrack = dpCrack, leakage = leakage, speed = 1) "The boiler pump, at one speed, and the check valve in its flange"
      annotation(Placement(transformation(origin = {366, -184.5}, extent = {{-12, -12}, {12, 12}}, rotation = -90)));

  protected
    parameter Real cWater(unit = "J/(m3.K)") = rhoWater * cpWater;
    Real EHeatPump(unit = "J", start = 0, fixed = true);
    Real EBoiler(unit = "J", start = 0, fixed = true);
    Real ELoss(unit = "J", start = 0, fixed = true);

  equation
    connect(heatPump.outlet, hpCheck.port_a)
      annotation(Line(points = {{1342.5, -225}, {1306.5, -225}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hpCheck.port_b, hpSupply.port_a)
      annotation(Line(points = {{1282.5, -225}, {1246.5, -225}, {1246.5, -204}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hpSupply.port_b, primaryMeter.port_a)
      annotation(Line(points = {{1246.5, -180}, {1246.5, -162}}, color = {0, 90, 180}, thickness = 0.5));
    connect(primaryMeter.port_b, siegValve.common)
      annotation(Line(points = {{1246.5, -138}, {1246.5, -117}, {1083, -117}}, color = {0, 90, 180}, thickness = 0.5));
    connect(siegValve.driven, siegKeepPipe.port_a)
      annotation(Line(points = {{1071, -129}, {1071, -145.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(siegKeepPipe.port_b, siegMeter.port_a)
      annotation(Line(points = {{1071, -169.5}, {1071, -187.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(siegMeter.port_b, siegTee.port_a)
      annotation(Line(points = {{1071, -211.5}, {1071, -225}}, color = {0, 90, 180}, thickness = 0.5));
    connect(siegTee.port_b, primaryPump.port_a)
      annotation(Line(points = {{1071, -249}, {1071, -255}, {1168.5, -255}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hpReturn.port_b, siegTee.port_b)
      annotation(Line(points = {{1002, -363}, {1002, -255}, {1071, -255}, {1071, -249}}, color = {0, 90, 180}, thickness = 0.5));
    connect(primaryPump.port_b, heatPump.inlet)
      annotation(Line(points = {{1192.5, -255}, {1342.5, -255}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldHeader.port_b, hpReturn.port_a)
      annotation(Line(points = {{897, -475.5}, {1002, -475.5}, {1002, -387}}, color = {0, 90, 180}, thickness = 0.5));
    connect(siegValve.rest, hotHeader.port_b)
      annotation(Line(points = {{1059, -117}, {939, -117}, {939, -193.5}, {897, -193.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(isoValve.port_b, hotHeader.port_a)
      annotation(Line(points = {{766.5, -193.5}, {873, -193.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotHeader.port_a, storeHot.port_a)
      annotation(Line(points = {{873, -193.5}, {796.5, -193.5}, {796.5, -157.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storeHot.port_b, hotPipe.port_a)
      annotation(Line(points = {{796.5, -133.5}, {796.5, -103.5}, {954, -103.5}, {954, -325.5}, {1242, -325.5}, {1242, -490.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotPipe.port_b, hotPipeToTank.port_a)
      annotation(Line(points = {{1242, -514.5}, {1242, -708}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotPipeToTank.port_b, hotTank.top)
      annotation(Line(points = {{1242, -732}, {1242, -919.5}, {1098, -919.5}, {1098, -937.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotTank.bottom, hotToMiddle.port_a)
      annotation(Line(points = {{1098, -1072.5}, {1098, -1092}, {1188, -1092}, {1188, -852}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hotToMiddle.port_b, middleTank.top)
      annotation(Line(points = {{1188, -828}, {1188, -717}, {1098, -717}, {1098, -735}}, color = {0, 90, 180}, thickness = 0.5));
    connect(middleTank.bottom, middleToCold.port_a)
      annotation(Line(points = {{1098, -870}, {1098, -888}, {1167, -888}, {1167, -807}}, color = {0, 90, 180}, thickness = 0.5));
    connect(middleToCold.port_b, coldTank.top)
      annotation(Line(points = {{1167, -783}, {1167, -514.5}, {1098, -514.5}, {1098, -532.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldTank.bottom, coldTankToPipe.port_a)
      annotation(Line(points = {{1098, -667.5}, {1098, -690}, {1209, -690}, {1209, -642}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldTankToPipe.port_b, coldPipe.port_a)
      annotation(Line(points = {{1209, -618}, {1209, -417}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldPipe.port_b, storeCold.port_a)
      annotation(Line(points = {{1209, -393}, {1209, -292.5}, {1092, -292.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storeCold.port_b, chargeValve.common)
      annotation(Line(points = {{1068, -292.5}, {976.5, -292.5}, {976.5, -208.5}, {780, -208.5}, {780, -243}}, color = {0, 90, 180}, thickness = 0.5));
    connect(chargeValve.driven, coldHeader.port_a)
      annotation(Line(points = {{792, -255}, {856.5, -255}, {856.5, -475.5}, {873, -475.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(chargeValve.rest, storePumpOutlet.port_b)
      annotation(Line(points = {{780, -267}, {780, -288}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storePump.port_b, storePumpOutlet.port_a)
      annotation(Line(points = {{780, -330}, {780, -312}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storePumpInlet.port_b, storePump.port_a)
      annotation(Line(points = {{780, -370.5}, {780, -354}}, color = {0, 90, 180}, thickness = 0.5));
    connect(storeMeter.port_b, storePumpInlet.port_a)
      annotation(Line(points = {{780, -411}, {780, -394.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldHeader.port_a, storeMeter.port_a)
      annotation(Line(points = {{873, -475.5}, {780, -475.5}, {780, -435}}, color = {0, 90, 180}, thickness = 0.5));
    connect(bufferBottom.port_b, bufferColdTee.port_a)
      annotation(Line(points = {{594, -463.5}, {594, -475.5}, {648, -475.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(bufferColdTee.port_b, coldRun.port_a)
      annotation(Line(points = {{672, -475.5}, {726, -475.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldRun.port_b, coldHeader.port_a)
      annotation(Line(points = {{750, -475.5}, {873, -475.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(buffer.bottom, bufferBottom.port_a)
      annotation(Line(points = {{594, -427.5}, {594, -439.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(buffer.top, bufferTop.port_a)
      annotation(Line(points = {{594, -217.5}, {594, -193.5}, {637.5, -193.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(bufferTop.port_b, bufferHotTee.port_a)
      annotation(Line(points = {{661.5, -193.5}, {699, -193.5}, {699, -208.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(bufferHotTee.port_a, isoValve.port_a)
      annotation(Line(points = {{699, -208.5}, {699, -193.5}, {742.5, -193.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(bufferHotTee.port_b, distSupply.port_a)
      annotation(Line(points = {{699, -232.5}, {699, -438}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distSupply.port_b, airSeparator.port_b)
      annotation(Line(points = {{699, -462}, {699, -741}, {643.5, -741}}, color = {0, 90, 180}, thickness = 0.5));
    connect(airSeparator.port_a, distPump.port_a)
      annotation(Line(points = {{619.5, -741}, {552, -741}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distPump.port_b, supplyManifold.port_b)
      annotation(Line(points = {{528, -741}, {489, -741}}, color = {0, 90, 180}, thickness = 0.5));
    connect(supplyManifold.port_a, zones.supply)
      annotation(Line(points = {{465, -741}, {438, -741}, {438, -664.5}, {336, -664.5}, {336, -711}}, color = {0, 90, 180}, thickness = 0.5));
    connect(zones.ret, returnManifold.port_a)
      annotation(Line(points = {{336, -825}, {336, -843}, {225, -843}, {225, -762}}, color = {0, 90, 180}, thickness = 0.5));
    connect(expansion.port, returnManifold.port_a)
      annotation(Line(points = {{180, -915}, {180, -870}, {225, -870}, {225, -762}}, color = {0, 90, 180}, thickness = 0.5));
    connect(returnManifold.port_b, distMeter.port_a)
      annotation(Line(points = {{225, -738}, {225, -645}, {333, -645}}, color = {0, 90, 180}, thickness = 0.5));
    connect(distMeter.port_b, bufferColdTee.port_a)
      annotation(Line(points = {{357, -645}, {417, -645}, {417, -475.5}, {648, -475.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(coldHeader.port_b, boilerPump.port_a)
      annotation(Line(points = {{897, -475.5}, {912, -475.5}, {912, -75}, {366, -75}, {366, -172.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(boilerPump.port_b, boiler.inlet)
      annotation(Line(points = {{366, -196.5}, {366, -318}, {295.5, -318}}, color = {0, 90, 180}, thickness = 0.5));
    connect(boiler.outlet, boilerCheck.port_a)
      annotation(Line(points = {{295.5, -237}, {330, -237}, {330, -124.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(boilerCheck.port_b, hotHeader.port_a)
      annotation(Line(points = {{330, -100.5}, {330, -57}, {859.5, -57}, {859.5, -193.5}, {873, -193.5}}, color = {0, 90, 180}, thickness = 0.5));
    connect(hpEnable, heatPump.call)
      annotation(Line(points = {{1365, -112.5}, {1365, -150}}, color = {0, 0, 127}));
    connect(hpScadaControl, heatPump.scadaControl)
      annotation(Line(points = {{1387.5, -112.5}, {1387.5, -150}}, color = {0, 0, 127}));
    connect(TOutdoor, heatPump.TOutdoor)
      annotation(Line(points = {{1410, -112.5}, {1410, -150}}, color = {0, 0, 127}));
    connect(TOutdoor, zones.TOutdoor)
      annotation(Line(points = {{1410, -112.5}, {1507.5, -112.5}, {1507.5, -1162.5}, {142.5, -1162.5}, {142.5, -796.5}, {276, -796.5}}, color = {0, 0, 127}));
    connect(primaryPumpOn, primaryPump.on)
      annotation(Line(points = {{1173.3, -210}, {1173.3, -243}}, color = {0, 0, 127}));
    connect(primaryPumpSpeed, primaryPump.speed)
      annotation(Line(points = {{1187.7, -210}, {1187.7, -243}}, color = {0, 0, 127}));
    connect(siegMotorOn, siegMotor.on)
      annotation(Line(points = {{1081.5, -18}, {1081.5, -51}}, color = {0, 0, 127}));
    connect(siegTowardKeep, siegMotor.toward)
      annotation(Line(points = {{1060.5, -18}, {1060.5, -51}}, color = {0, 0, 127}));
    connect(siegMotor.position, siegValve.position)
      annotation(Line(points = {{1071, -75}, {1071, -105}}, color = {0, 0, 127}));
    connect(chargeDischarge, isoPosition.u)
      annotation(Line(points = {{754.5, -33}, {754.5, -135}}, color = {0, 0, 127}));
    connect(isoPosition.y, isoValve.position)
      annotation(Line(points = {{754.5, -159}, {754.5, -181.5}}, color = {0, 0, 127}));
    connect(chargeDischarge, chargeValve.position)
      annotation(Line(points = {{754.5, -33}, {732, -33}, {732, -255}, {768, -255}}, color = {0, 0, 127}));
    connect(storePumpOn, storePump.on)
      annotation(Line(points = {{750, -349.2}, {768, -349.2}}, color = {0, 0, 127}));
    connect(storePumpSpeed, storePump.speed)
      annotation(Line(points = {{750, -334.8}, {768, -334.8}}, color = {0, 0, 127}));
    connect(zones.call, distPump.on)
      annotation(Line(points = {{396, -796.5}, {450, -796.5}, {450, -877.5}, {547.2, -877.5}, {547.2, -753}}, color = {0, 0, 127}));
    connect(distPumpSpeed, distPump.speed)
      annotation(Line(points = {{532.8, -780}, {532.8, -753}}, color = {0, 0, 127}));
    connect(zoneScadaControl, zones.scadaControl)
      annotation(Line(points = {{354, -870}, {354, -825}}, color = {0, 0, 127}));
    connect(zoneScadaCall, zones.scadaCall)
      annotation(Line(points = {{378, -870}, {378, -825}}, color = {0, 0, 127}));
    connect(boilerCall, boiler.call)
      annotation(Line(points = {{120, -277.5}, {175.5, -277.5}}, color = {0, 0, 127}));
    connect(boilerCall, boilerPump.on)
      annotation(Line(points = {{120, -277.5}, {120, -150}, {405, -150}, {405, -177.3}, {378, -177.3}}, color = {0, 0, 127}));

    hpLwt = heatPump.T;
    hpEwt = siegTee.T;
    primaryFlow = primaryMeter.reading;
    siegFlow = siegMeter.reading;
    siegHot = siegKeepPipe.T;
    siegCold = coldHeader.T;
    siegKeep = siegMotor.position;
    bufferHotPipe = bufferHotTee.T;
    bufferDepth = buffer.TSensor;
    distSwt = airSeparator.T;
    distRwt = returnManifold.T;
    distFlow = distMeter.reading;
    storeHotPipe = hotPipe.T;
    storeColdPipe = coldPipe.T;
    storeFlow = storeMeter.reading;
    hpOduPower = heatPump.oduPower;
    hpIduPower = heatPump.iduPower;
    primaryPumpPower = primaryPump.power;
    storePumpPower = storePump.power;
    distPumpPower = distPump.power;
    oilBoilerPower = boiler.power + boilerPump.power;
    zoneTemperature = zones.TZone;
    zoneCallPower = zones.callPower;
    heatPumpHeat = heatPump.Q;
    boilerHeat = boiler.Q;
    storeCharge = storeHot.q;
    heatPumpEnergy = EHeatPump;
    boilerEnergy = EBoiler;
    lossEnergy = ELoss;
    tankDepth[1, :] = hotTank.TSensor;
    tankDepth[2, :] = middleTank.TSensor;
    tankDepth[3, :] = coldTank.TSensor;

    der(EHeatPump) = heatPump.Q;
    der(EBoiler) = boiler.Q;
    der(ELoss) = heatPump.QLoss + hpSupply.QLoss + siegValve.QLoss + siegKeepPipe.QLoss + siegTee.QLoss + hotHeader.QLoss
      + bufferHotTee.QLoss + buffer.QLoss + bufferColdTee.QLoss + coldHeader.QLoss + airSeparator.QLoss + supplyManifold.QLoss
      + zones.QLoss + returnManifold.QLoss + hotPipe.QLoss + hotTank.QLoss + middleTank.QLoss + coldTank.QLoss
      + coldPipe.QLoss + chargeValve.QLoss + storePumpOutlet.QLoss + storePumpInlet.QLoss + boiler.QLoss;
    thermalEnergy = heatPump.E + hpSupply.E + siegValve.E + siegKeepPipe.E + siegTee.E + hotHeader.E
      + bufferHotTee.E + buffer.E + bufferColdTee.E + coldHeader.E + airSeparator.E + supplyManifold.E
      + zones.E + returnManifold.E + hotPipe.E + hotTank.E + middleTank.E + coldTank.E
      + coldPipe.E + chargeValve.E + storePumpOutlet.E + storePumpInlet.E + boiler.E;
    annotation(
      experiment(StartTime = 0, StopTime = 86400, Tolerance = 1e-6, Interval = 60),
      Diagram(coordinateSystem(extent = {{0, -1200}, {1890, 90}}, preserveAspectRatio = true), graphics = {
        Rectangle(extent = {{1305, -375}, {1410, -585}}, lineColor = {0, 0, 0}, fillColor = {235, 235, 235}, fillPattern = FillPattern.Solid),
        Ellipse(extent = {{1320, -390}, {1395, -465}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
        Ellipse(extent = {{1320, -495}, {1395, -570}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
        Line(points = {{1365, -270}, {1365, -375}}, color = {255, 190, 0}, thickness = 1),
        Line(points = {{1380, -270}, {1380, -375}}, color = {255, 190, 0}, thickness = 1),
        Text(extent = {{1290, -595}, {1425, -625}}, textString = "outdoor unit", textColor = {0, 0, 0})}),
      Icon(graphics = {
        Rectangle(extent = {{-100, -100}, {100, 100}}, lineColor = {0, 0, 0}, fillColor = {255, 255, 255}, fillPattern = FillPattern.Solid),
        Text(extent = {{-90, 30}, {90, -30}}, textString = "%name", textColor = {0, 0, 0})}),
      Documentation(info = "<html><p>The pipework of the Beech schematic, built of the parts in Hydronic. The outdoor unit is drawn and not modelled apart from the indoor unit: the heat pump is one part.</p></html>"));
  end Plant;
end Beech;
