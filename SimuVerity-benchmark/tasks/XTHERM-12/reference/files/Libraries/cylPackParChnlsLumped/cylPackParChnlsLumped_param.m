%% Battery parameters

%% ModuleType1
ModuleType1.SOC_vecCell = [0, .1, .25, .5, .75, .9, 1]; % Vector of state-of-charge values, SOC
ModuleType1.T_vecCell = [278, 293, 313]; % Vector of temperatures, T, K
ModuleType1.V0_matCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, V0(SOC,T), V
ModuleType1.V_rangeCell = [0, inf]; % Terminal voltage operating range [Min Max], V
ModuleType1.R0_matCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Terminal resistance, R0(SOC,T), Ohm
ModuleType1.AHCell = 27; % Cell capacity, AH, A*hr
ModuleType1.thermal_massCell = 100; % Thermal mass, J/K
ModuleType1.CoolantResistance = 1.2; % Cell level coolant thermal path resistance, K/W
ModuleType1.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType1
ParallelAssemblyType1.SOC_vecCell = [0, .1, .25, .5, .75, .9, 1]; % Vector of state-of-charge values, SOC
ParallelAssemblyType1.T_vecCell = [278, 293, 313]; % Vector of temperatures, T, K
ParallelAssemblyType1.V0_matCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, V0(SOC,T), V
ParallelAssemblyType1.V_rangeCell = [0, inf]; % Terminal voltage operating range [Min Max], V
ParallelAssemblyType1.R0_matCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Terminal resistance, R0(SOC,T), Ohm
ParallelAssemblyType1.AHCell = 27; % Cell capacity, AH, A*hr
ParallelAssemblyType1.thermal_massCell = 100; % Thermal mass, J/K
ParallelAssemblyType1.CoolantResistance = 1.2; % Cell level coolant thermal path resistance, K/W
ParallelAssemblyType1.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% Cooling Plates

%% CoolingPlateBottom
CoolingPlateBottom.numBattThermalNodes1 = 8; % 电池热节点的数目(表面 1)
CoolingPlateBottom.dimensionThermalNodes1 = [[0.671 0.251;0.671 0.251;0.671 0.251;0.671 0.251;0.671 0.251;0.671 0.251;0.671 0.250999999999999;0.671 0.250999999999999]]; % 电池热节点的维度(表面 1)
CoolingPlateBottom.locationThermalNodes1 = [[0.3355 0.1255;1.0075 0.1255;0.3355 0.4665;1.0075 0.4665;0.3355 0.8075;1.0075 0.8075;0.3355 1.1485;1.0075 1.1485]]; % 电池热节点的坐标(表面 1)
CoolingPlateBottom.plateDimX = 2; % 冷却板在 X 维度的分区数
CoolingPlateBottom.plateDimY = 5; % 冷却板在 Y 维度的分区数
CoolingPlateBottom.plateTh = 2e-3; % 冷却板材料的厚度, m
CoolingPlateBottom.plateThCond = 20; % 冷却板材料的热导率, W/(K*m)
CoolingPlateBottom.plateDen = 2500; % 冷却板材料的密度, kg/m^3
CoolingPlateBottom.plateCp = 447; % 冷却板材料的比热, J/(K*kg)
CoolingPlateBottom.plateTemp_ini = 300; % 冷却板和冷却液流体的初始温度, K
CoolingPlateBottom.Re_lam = 2000; % 层流的雷诺数上限
CoolingPlateBottom.Re_tur = 4000; % 湍流的雷诺数下限
CoolingPlateBottom.Nu_lam = 3.66; % 层流传热的努塞尔数
CoolingPlateBottom.length_add = 1e-3; % 局部阻力的总等效长度, m
CoolingPlateBottom.shape_factor = 64; % 达西摩擦因子的层流摩擦常量
CoolingPlateBottom.nChannels = 4; % 冷却液通道数
CoolingPlateBottom.channelDia = 0.005; % 冷却液通道的水力直径, m
CoolingPlateBottom.distributorDia = 0.005; % 分配管道的直径, m
CoolingPlateBottom.roughnessPipe = 1.5e-05; % 冷却液通道和分配通道的粗糙度, m

%% Battery initial targets

%% ModuleAssembly1.Module1
ModuleAssembly1.Module1.iCell = 0; % Cell current (positive in), A
ModuleAssembly1.Module1.vCell = 0; % Cell terminal voltage, V
ModuleAssembly1.Module1.socCell = 1; % Cell state of charge
ModuleAssembly1.Module1.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly1.Module1.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly1.Module1.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly1.Module1.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly1.Module2
ModuleAssembly1.Module2.iCell = 0; % Cell current (positive in), A
ModuleAssembly1.Module2.vCell = 0; % Cell terminal voltage, V
ModuleAssembly1.Module2.socCell = 1; % Cell state of charge
ModuleAssembly1.Module2.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly1.Module2.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly1.Module2.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly1.Module2.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly2.Module1
ModuleAssembly2.Module1.iCell = 0; % Cell current (positive in), A
ModuleAssembly2.Module1.vCell = 0; % Cell terminal voltage, V
ModuleAssembly2.Module1.socCell = 1; % Cell state of charge
ModuleAssembly2.Module1.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly2.Module1.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly2.Module1.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly2.Module1.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly2.Module2
ModuleAssembly2.Module2.iCell = 0; % Cell current (positive in), A
ModuleAssembly2.Module2.vCell = 0; % Cell terminal voltage, V
ModuleAssembly2.Module2.socCell = 1; % Cell state of charge
ModuleAssembly2.Module2.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly2.Module2.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly2.Module2.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly2.Module2.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly3.Module1
ModuleAssembly3.Module1.iCell = 0; % Cell current (positive in), A
ModuleAssembly3.Module1.vCell = 0; % Cell terminal voltage, V
ModuleAssembly3.Module1.socCell = 1; % Cell state of charge
ModuleAssembly3.Module1.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly3.Module1.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly3.Module1.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly3.Module1.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly3.Module2
ModuleAssembly3.Module2.iCell = 0; % Cell current (positive in), A
ModuleAssembly3.Module2.vCell = 0; % Cell terminal voltage, V
ModuleAssembly3.Module2.socCell = 1; % Cell state of charge
ModuleAssembly3.Module2.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly3.Module2.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly3.Module2.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly3.Module2.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly4.Module1
ModuleAssembly4.Module1.iCell = 0; % Cell current (positive in), A
ModuleAssembly4.Module1.vCell = 0; % Cell terminal voltage, V
ModuleAssembly4.Module1.socCell = 1; % Cell state of charge
ModuleAssembly4.Module1.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly4.Module1.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly4.Module1.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly4.Module1.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

%% ModuleAssembly4.Module2
ModuleAssembly4.Module2.iCell = 0; % Cell current (positive in), A
ModuleAssembly4.Module2.vCell = 0; % Cell terminal voltage, V
ModuleAssembly4.Module2.socCell = 1; % Cell state of charge
ModuleAssembly4.Module2.numCyclesCell = 0; % Cell discharge cycles
ModuleAssembly4.Module2.temperatureCell = 298.15; % Cell temperature, K
ModuleAssembly4.Module2.vParallelAssembly = repmat(0, 12, 1); % Parallel Assembly Voltage, V
ModuleAssembly4.Module2.socParallelAssembly = repmat(1, 12, 1); % Parallel Assembly state of charge

% Suppress MATLAB editor message regarding readability of repmat
%#ok<*REPMAT>
