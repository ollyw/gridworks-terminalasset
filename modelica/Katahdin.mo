package Katahdin
  "The Katahdin monobloc heating plant: a glycol primary loop, a plate exchanger, a three-tank water store and a zoned distribution loop"

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

  model Plant
    "Valve positions, pump commands and weather in; every sensed temperature, flow and power out"

    constant Integer nZones = 4 "Zones on the distribution loop";
    constant Integer nSeg = 9 "Layers in each store tank";
    constant Integer nCells = 3 * nSeg "Layers in the store, hot tank top first";
    constant Integer nHot = 2 * nSeg "Layers above the junction: the hot and middle tanks";
    constant Integer sensorCell[3] = {2, 5, 8} "Layer read by each depth sensor of a tank, top first";

    input Real v1Position(start = 0) "V1, exchanger to supply header: 0 closed, 1 open";
    input Real v2Position(start = 1) "V2, supply header to hot tank top: 0 closed, 1 open";
    input Real v3Position(start = 0) "V3, supply header to cold tank top: 0 closed, 1 open";
    input Real v4Position(start = 0) "V4, house return to return header: 0 closed, 1 open";
    input Real v5Position(start = 0) "V5, house return to boiler: 0 closed, 1 open";
    input Real secondaryPumpOn(start = 0) "Pump 2 relay: 0 off, 1 on";
    input Real secondaryPumpSpeed(start = 1) "Pump 2 speed as a fraction of full";
    input Real distPumpSpeed(start = 1) "Distribution circulator speed as a fraction of full";
    input Real hpEnable(start = 0) "The scada's call for the heat pump: 0 no call, 1 call";
    input Real hpScadaControl(start = 1) "Who holds the heat pump's call: 0 its aquastat, which makes none here, 1 the scada";
    input Real TOutdoor(unit = "K", start = 268.15) "Outdoor air temperature";

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

    output Real hpLwt(unit = "K") "Glycol leaving the heat pump";
    output Real hpEwt(unit = "K") "Glycol entering the heat pump";
    output Real secondaryLwt(unit = "K") "Water leaving the exchanger";
    output Real secondaryEwt(unit = "K") "Water entering the exchanger";
    output Real distSwt(unit = "K") "Water supplied to the house";
    output Real distRwt(unit = "K") "Water returning from the house";
    output Real storeHotPipe(unit = "K") "Pipe at the hot tank top";
    output Real storeColdPipe(unit = "K") "Pipe at the cold tank bottom";
    output Real tankDepth[3, 3](each unit = "K") "Tank (hot, middle, cold) by depth (top, middle, bottom)";
    output Real primaryFlow(unit = "m3/s");
    output Real secondaryFlow(unit = "m3/s");
    output Real distFlow(unit = "m3/s");
    output Real storeFlow(unit = "m3/s") "Magnitude only: the meter does not tell charge from discharge";
    output Real hpOduPower(unit = "W");
    output Real hpCtrlBoxPower(unit = "W");
    output Real distPumpPower(unit = "W");
    output Real secondaryPumpPower(unit = "W");
    output Real zoneTemperature[nZones](each unit = "K");
    output Real zoneCallPower[nZones](each unit = "W") "Power on each zone's thermostat wire";
    output Real heatPumpHeat(unit = "W") "Heat the heat pump is putting into the glycol";
    output Real storeCharge(unit = "m3/s") "Store flow signed: positive into a tank top";
    output Real thermalEnergy(unit = "J") "Heat held by every volume and zone, above 0 degC";
    output Real heatPumpEnergy(unit = "J") "Heat delivered by the heat pump since time zero";
    output Real lossEnergy(unit = "J") "Heat lost to the room and the outdoor air since time zero";

  protected
    parameter Real cWater(unit = "J/(m3.K)") = rhoWater * cpWater;
    parameter Real cGlycol(unit = "J/(m3.K)") = rhoGlycol * cpGlycol;
    parameter Real kPump(unit = "Pa.s/m3") = dpPumpShutoff / VFlowPumpMax;
    parameter Real RSecondary = dpSecondaryNominal / VFlowNominal;
    parameter Real RStoreHot = dpStoreHotNominal / VFlowNominal;
    parameter Real RStoreMid = dpStoreMidNominal / VFlowNominal;
    parameter Real RStoreCold = dpStoreColdNominal / VFlowNominal;
    parameter Real RSupply = dpSupplyNominal / VFlowNominal;
    parameter Real RReturn = dpReturnNominal / VFlowNominal;
    parameter Real RBoiler = dpBoilerNominal / VFlowNominal;
    parameter Real RZone = dpZoneNominal / VFlowZoneNominal;
    parameter Real CCell(unit = "J/K") = cWater * VTank / nSeg;
    parameter Real UACell(unit = "W/K") = UATank / nSeg;
    parameter Real GConduction(unit = "W/K") = kTankEffective * (VTank / hTank) / (hTank / nSeg);
    parameter Real GBuoyancy(unit = "W/K") = CCell / tauBuoyancy;
    parameter Real CPipe(unit = "J/K") = cWater * VPipe;
    parameter Real CVolumizer(unit = "J/K") = cGlycol * VVolumizer;
    constant Real T0(unit = "K") = 273.15;

    Real v1 = min(max(v1Position, 0), 1);
    Real v2 = min(max(v2Position, 0), 1);
    Real v3 = min(max(v3Position, 0), 1);
    Real v4 = min(max(v4Position, 0), 1);
    Real v5 = min(max(v5Position, 0), 1);
    Real speedSecondary = min(max(secondaryPumpOn, 0), 1) * min(max(secondaryPumpSpeed, 0), 1);
    Real speedDist = min(max(distPumpSpeed, 0), 1);
    Real enable = min(max(hpEnable, 0), 1) * min(max(hpScadaControl, 0), 1);

    Real pSupply(unit = "Pa") "Supply header, above the return header";
    Real pJunction(unit = "Pa") "Middle tank bottom and cold tank top";
    Real pHouseSupply(unit = "Pa") "House supply tee";
    Real pHouseReturn(unit = "Pa") "House return tee, downstream of the circulator";
    Real qSecondary(unit = "m3/s") "Return header through the exchanger to the supply header";
    Real qHot(unit = "m3/s") "Supply header through V2 down the hot and middle tanks";
    Real qMid(unit = "m3/s") "Supply header through V3 to the junction";
    Real qCold(unit = "m3/s") "Junction down the cold tank to the return header";
    Real qSupply(unit = "m3/s") "Supply header to the house supply tee";
    Real qReturn(unit = "m3/s") "House return tee through V4 to the return header";
    Real qEmitters(unit = "m3/s") "House supply tee through the zones and circulator to the return tee";
    Real qBoiler(unit = "m3/s") "House return tee through V5 and the boiler to the supply tee";
    Real qZone[nZones](each unit = "m3/s");
    Real qPrimary(unit = "m3/s");
    Real GZone[nZones];
    Real GZoneSum;

    Real qSecondaryPos = noEvent(max(qSecondary, 0));
    Real qSecondaryNeg = noEvent(max(-qSecondary, 0));
    Real qHotPos = noEvent(max(qHot, 0));
    Real qHotNeg = noEvent(max(-qHot, 0));
    Real qMidPos = noEvent(max(qMid, 0));
    Real qMidNeg = noEvent(max(-qMid, 0));
    Real qColdPos = noEvent(max(qCold, 0));
    Real qColdNeg = noEvent(max(-qCold, 0));
    Real qSupplyPos = noEvent(max(qSupply, 0));
    Real qSupplyNeg = noEvent(max(-qSupply, 0));
    Real qReturnPos = noEvent(max(qReturn, 0));
    Real qReturnNeg = noEvent(max(-qReturn, 0));
    Real qBoilerPos = noEvent(max(qBoiler, 0));
    Real qBoilerNeg = noEvent(max(-qBoiler, 0));
    Real qZonePos[nZones] = {noEvent(max(qZone[i], 0)) for i in 1:nZones};
    Real qZoneNeg[nZones] = {noEvent(max(-qZone[i], 0)) for i in 1:nZones};

    Real THeatPump(unit = "K", start = TStartPlant, fixed = true);
    Real TExchangerGlycol(unit = "K", start = TStartPlant, fixed = true);
    Real TVolumizer(unit = "K", start = TStartPlant, fixed = true);
    Real TExchangerWater(unit = "K", start = TStartPlant, fixed = true);
    Real TSupplyHeader(unit = "K", start = TStartPlant, fixed = true);
    Real TReturnHeader(unit = "K", start = TStartPlant, fixed = true);
    Real THotPipe(unit = "K", start = TStartPlant, fixed = true);
    Real TMidPipe(unit = "K", start = TStartPlant, fixed = true);
    Real TColdPipe(unit = "K", start = TStartPlant, fixed = true);
    Real TJunction(unit = "K", start = TStartPlant, fixed = true);
    Real TTank[nCells](each unit = "K", each start = TStartPlant, each fixed = true);
    Real TDistSupply(unit = "K", start = TStartPlant, fixed = true);
    Real TDistReturn(unit = "K", start = TStartPlant, fixed = true);
    Real THouseSupply(unit = "K", start = TStartPlant, fixed = true);
    Real THouseReturn(unit = "K", start = TStartPlant, fixed = true);
    Real TBoiler(unit = "K", start = TStartPlant, fixed = true);
    Real TEmitter[nZones](each unit = "K", each start = TStartPlant, each fixed = true);
    Real TZone[nZones](each unit = "K", each start = TStartZone, each fixed = true);
    Real EHeatPump(unit = "J", start = 0, fixed = true);
    Real ELoss(unit = "J", start = 0, fixed = true);

    Real TAbove[nCells](each unit = "K") "What flows into a layer when the flow is downward";
    Real TBelow[nCells](each unit = "K") "What flows into a layer when the flow is upward";
    Real qCellDown[nCells](each unit = "m3/s");
    Real qCellUp[nCells](each unit = "m3/s");
    Real QDown[nCells](each unit = "W") "Heat passing from a layer to the one beneath it in the same tank";

    Boolean zoneCalling[nZones](each start = false, each fixed = true);
    Real zonePosition[nZones];
    Real anyZoneOpen;
    Boolean lwtPermit(start = true, fixed = true);
    Real compressor "1 while the compressor runs";
    Real QHeatPump(unit = "W");
    Real PCompressor(unit = "W");
    Real capacityWater(unit = "W/K");
    Real capacityGlycol(unit = "W/K");
    Real capacityMin(unit = "W/K");
    Real capacityMax(unit = "W/K");
    Real TExchangerWaterIn(unit = "K");
    Real QExchanger(unit = "W") "Heat passing from glycol to water";
    Real QLoss(unit = "W");

  equation
    qSecondary = (dpPumpShutoff * speedSecondary ^ 2 - pSupply)
      / (RSecondary / (leakage + (1 - leakage) * v1) + kPump);
    qHot = (leakage + (1 - leakage) * v2) / RStoreHot * (pSupply - pJunction);
    qMid = (leakage + (1 - leakage) * v3) / RStoreMid * (pSupply - pJunction);
    qCold = pJunction / RStoreCold;
    qSupply = (pSupply - pHouseSupply) / RSupply;
    qReturn = (leakage + (1 - leakage) * v4) / RReturn * pHouseReturn;
    qBoiler = (leakage + (1 - leakage) * v5) / RBoiler * (pHouseReturn - pHouseSupply);
    qEmitters = (pHouseSupply - pHouseReturn + dpPumpShutoff * speedDist ^ 2 * anyZoneOpen)
      / (1 / GZoneSum + kPump);
    0 = qSecondary - qHot - qMid - qSupply;
    0 = qHot + qMid - qCold;
    0 = qSupply + qBoiler - qEmitters;
    0 = qEmitters - qBoiler - qReturn;

    for i in 1:nZones loop
      zoneCalling[i] = if pre(zoneCalling[i]) then TZone[i] < TZoneSet + dTZoneDeadband / 2
        else TZone[i] < TZoneSet - dTZoneDeadband / 2;
      zonePosition[i] = if zoneCalling[i] then 1 else 0;
      GZone[i] = (leakage + (1 - leakage) * zonePosition[i]) / RZone;
      qZone[i] = qEmitters * GZone[i] / GZoneSum;
    end for;
    GZoneSum = sum(GZone);
    anyZoneOpen = min(sum(zonePosition), 1);
    qPrimary = VFlowPrimaryNominal * enable;

    lwtPermit = if pre(lwtPermit) then THeatPump < TLwtMax else THeatPump < TLwtMax - dTLwtRestart;
    compressor = enable * (if lwtPermit then 1 else 0);
    QHeatPump = compressor * bilinear(TOutdoor, THeatPump, TOutdoorGrid, TLwtGrid, QHeatPumpTable);
    PCompressor = QHeatPump / bilinear(TOutdoor, THeatPump, TOutdoorGrid, TLwtGrid, COPTable);

    capacityWater = cWater * noEvent(abs(qSecondary));
    capacityGlycol = cGlycol * qPrimary;
    capacityMin = noEvent(max(min(capacityWater, capacityGlycol), 1e-3));
    capacityMax = noEvent(max(max(capacityWater, capacityGlycol), 1e-3));
    TExchangerWaterIn = noEvent(if qSecondary >= 0 then TReturnHeader else TSupplyHeader);
    QExchanger = counterflowEffectiveness(UAExchanger / capacityMin, capacityMin / capacityMax)
      * capacityMin * (THeatPump - TExchangerWaterIn)
      + UAExchangerStatic * (TExchangerGlycol - TExchangerWater);

    CHeatPump * der(THeatPump) = cGlycol * qPrimary * (TVolumizer - THeatPump) + QHeatPump
      - UAHeatPump * (THeatPump - TOutdoor);
    CExchangerSide * der(TExchangerGlycol) = cGlycol * qPrimary * (THeatPump - TExchangerGlycol) - QExchanger
      - UAPipe * (TExchangerGlycol - TAmbient);
    CVolumizer * der(TVolumizer) = cGlycol * qPrimary * (TExchangerGlycol - TVolumizer)
      - UAVolumizer * (TVolumizer - TAmbient);

    CExchangerSide * der(TExchangerWater) = cWater * (qSecondaryPos * (TReturnHeader - TExchangerWater)
      + qSecondaryNeg * (TSupplyHeader - TExchangerWater)) + QExchanger
      - UAPipe * (TExchangerWater - TAmbient);
    CPipe * der(TSupplyHeader) = cWater * (qSecondaryPos * (TExchangerWater - TSupplyHeader)
      + qHotNeg * (THotPipe - TSupplyHeader) + qMidNeg * (TMidPipe - TSupplyHeader)
      + qSupplyNeg * (TDistSupply - TSupplyHeader)) - UAPipe * (TSupplyHeader - TAmbient);
    CPipe * der(TReturnHeader) = cWater * (qColdPos * (TColdPipe - TReturnHeader)
      + qReturnPos * (TDistReturn - TReturnHeader) + qSecondaryNeg * (TExchangerWater - TReturnHeader))
      - UAPipe * (TReturnHeader - TAmbient);
    CPipe * der(THotPipe) = cWater * (qHotPos * (TSupplyHeader - THotPipe) + qHotNeg * (TTank[1] - THotPipe))
      - UAPipe * (THotPipe - TAmbient);
    CPipe * der(TMidPipe) = cWater * (qMidPos * (TSupplyHeader - TMidPipe) + qMidNeg * (TJunction - TMidPipe))
      - UAPipe * (TMidPipe - TAmbient);
    CPipe * der(TJunction) = cWater * (qHotPos * (TTank[nHot] - TJunction) + qMidPos * (TMidPipe - TJunction)
      + qColdNeg * (TTank[nHot + 1] - TJunction)) - UAPipe * (TJunction - TAmbient);
    CPipe * der(TColdPipe) = cWater * (qColdPos * (TTank[nCells] - TColdPipe)
      + qColdNeg * (TReturnHeader - TColdPipe)) - UAPipe * (TColdPipe - TAmbient);

    for i in 1:nCells loop
      qCellDown[i] = if i <= nHot then qHotPos else qColdPos;
      qCellUp[i] = if i <= nHot then qHotNeg else qColdNeg;
      TAbove[i] = if i == 1 then THotPipe elseif i == nHot + 1 then TJunction else TTank[max(i - 1, 1)];
      TBelow[i] = if i == nHot then TJunction elseif i == nCells then TColdPipe else TTank[min(i + 1, nCells)];
      QDown[i] = if mod(i, nSeg) == 0 then 0
        else GConduction * (TTank[i] - TTank[min(i + 1, nCells)])
          - GBuoyancy * noEvent(max(TTank[min(i + 1, nCells)] - TTank[i], 0));
      CCell * der(TTank[i]) = cWater * (qCellDown[i] * (TAbove[i] - TTank[i]) + qCellUp[i] * (TBelow[i] - TTank[i]))
        + (if mod(i, nSeg) == 1 then 0 else QDown[max(i - 1, 1)]) - QDown[i]
        - UACell * (TTank[i] - TAmbient);
    end for;

    CPipe * der(TDistSupply) = cWater * (qSupplyPos * (TSupplyHeader - TDistSupply)
      + qSupplyNeg * (THouseSupply - TDistSupply)) - UAPipe * (TDistSupply - TAmbient);
    CPipe * der(THouseSupply) = cWater * (qSupplyPos * (TDistSupply - THouseSupply)
      + qBoilerPos * (TBoiler - THouseSupply)
      + sum(qZoneNeg[i] * (TEmitter[i] - THouseSupply) for i in 1:nZones))
      - UAPipe * (THouseSupply - TAmbient);
    CPipe * der(THouseReturn) = cWater * (sum(qZonePos[i] * (TEmitter[i] - THouseReturn) for i in 1:nZones)
      + qBoilerNeg * (TBoiler - THouseReturn) + qReturnNeg * (TDistReturn - THouseReturn))
      - UAPipe * (THouseReturn - TAmbient);
    CPipe * der(TDistReturn) = cWater * (qReturnPos * (THouseReturn - TDistReturn)
      + qReturnNeg * (TReturnHeader - TDistReturn)) - UAPipe * (TDistReturn - TAmbient);
    CBoiler * der(TBoiler) = cWater * (qBoilerPos * (THouseReturn - TBoiler) + qBoilerNeg * (THouseSupply - TBoiler))
      - UABoiler * (TBoiler - TAmbient);
    for i in 1:nZones loop
      CEmitter * der(TEmitter[i]) = cWater * (qZonePos[i] * (THouseSupply - TEmitter[i])
        + qZoneNeg[i] * (THouseReturn - TEmitter[i])) - UAEmitter * (TEmitter[i] - TZone[i]);
      CZone * der(TZone[i]) = UAEmitter * (TEmitter[i] - TZone[i]) - UAZone * (TZone[i] - TOutdoor);
    end for;

    QLoss = UAHeatPump * (THeatPump - TOutdoor) + UAVolumizer * (TVolumizer - TAmbient)
      + UAPipe * (TExchangerGlycol + TExchangerWater + TSupplyHeader + TReturnHeader + THotPipe + TMidPipe
        + TJunction + TColdPipe + TDistSupply + THouseSupply + THouseReturn + TDistReturn - 12 * TAmbient)
      + UACell * (sum(TTank) - nCells * TAmbient) + UABoiler * (TBoiler - TAmbient)
      + UAZone * (sum(TZone) - nZones * TOutdoor);
    der(EHeatPump) = QHeatPump;
    der(ELoss) = QLoss;

    hpLwt = THeatPump;
    hpEwt = TVolumizer;
    secondaryLwt = TExchangerWater;
    secondaryEwt = TReturnHeader;
    distSwt = TDistSupply;
    distRwt = TDistReturn;
    storeHotPipe = THotPipe;
    storeColdPipe = TColdPipe;
    for tank in 1:3 loop
      for depth in 1:3 loop
        tankDepth[tank, depth] = TTank[(tank - 1) * nSeg + sensorCell[depth]];
      end for;
    end for;
    primaryFlow = qPrimary;
    secondaryFlow = noEvent(if abs(qSecondary) < VFlowMeterMin then 0 else abs(qSecondary));
    distFlow = noEvent(if abs(qReturn) < VFlowMeterMin then 0 else abs(qReturn));
    storeFlow = noEvent(if abs(qCold) < VFlowMeterMin then 0 else abs(qCold));
    hpOduPower = PCompressor + PHeatPumpStandby;
    hpCtrlBoxPower = PControlBoxStandby + PPrimaryPump * enable;
    distPumpPower = PPumpNominal * speedDist ^ 3 * anyZoneOpen;
    secondaryPumpPower = PPumpNominal * speedSecondary ^ 3;
    zoneTemperature = TZone;
    zoneCallPower = PZoneValve * zonePosition;
    heatPumpHeat = QHeatPump;
    storeCharge = qCold;
    thermalEnergy = CHeatPump * (THeatPump - T0) + CExchangerSide * (TExchangerGlycol + TExchangerWater - 2 * T0)
      + CVolumizer * (TVolumizer - T0)
      + CPipe * (TSupplyHeader + TReturnHeader + THotPipe + TMidPipe + TJunction + TColdPipe
        + TDistSupply + THouseSupply + THouseReturn + TDistReturn - 10 * T0)
      + CCell * (sum(TTank) - nCells * T0) + CBoiler * (TBoiler - T0)
      + CEmitter * (sum(TEmitter) - nZones * T0) + CZone * (sum(TZone) - nZones * T0);
    heatPumpEnergy = EHeatPump;
    lossEnergy = ELoss;
  end Plant;
end Katahdin;
