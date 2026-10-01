classdef ComponentConnectivity
    % COMPONENTCONNECTIVITY: This class adds the required blocks for the
    %   cooling plate flow network in the model, connects them with each
    %   other and to the blocks for cooling plate thermal network and
    %   battery pack, and sets parameters for flow and thermal network.

    %   ComponentConnectivity properties:
    %       ModelName                      - Name of generated Simscape model.
    %       CoolingPlateSystem             - Full path to the Cooling Plate subsystem in the model.
    %       FlowSystem                     - Full path to the Flow Network subsystem in the Cooling Plate subsystem in the model.
    %       FlowSystemBusBlock             - Full path to the SimscapeBus block in the Flow Network subsystem in the model.
    %       FlowSystemThermalArrayConn     - Full path to the Array Connection block in the Flow Network subsystem in the model.
    %       LibBlockCoolingPlateThermal    - Full path to the Cooling Plate Connector library block in the coolingPlateThermal_lib custom Simulink library.
    %       CoolingPlateThermalComponent   - Full path to the Cooling Plate Connector block in the Cooling Plate subsystem in the model.
    %       CoolingPlateToBatteryArrayConn - Full path to the Array Connection block in the model.
    %       FlowSystemXRef                 - Reference X-coordinate inside Flow System subsystem in Simulink canvas.
    %       FlowSystemYRef                 - Reference Y-coordinate inside Flow System subsystem in Simulink canvas.
    %       ConnectivityData               - Data structure containing information about CAD components and their interconnections.
    %       MaterialProp                   - Cooling plate material properties.
    %       AllComponents                  - Names of all CAD components and extreme positions.
    %       NumComponents                  - Number of all CAD components.
    %       Component                      - Geometrical properties like coordinates, position, orientation, direction and number of discrete elements.
    %       Plate                          - Cooling plate geometrical properties like corner positions, partition width and partition height.
    %       DiscreteElement                - Discrete element properties like CAD position, length, block position, block handle, partition index.
    %       Partition                      - Partition corner points.
    %       Canvas                         - Flow network canvas scaling and block sizes.
    %       DiscreteElemPartition          - Partition index array for all discrete elements.
    %       Mask                           - Cooling plate subsystem mask properties.
    %
    %   ComponentConnectivity methods:
    %       ComponentConnectivity                - Constructor of this class.
    %       addFlowComponentsInModel             - Add blocks for the flow network components in the model.
    %       addThermalComponentInModel           - Add Simscape Component for the thermal network in the model.
    %       assignPositionsInSIUnit              - Convert component positions and centerline coordinates to SI unit and assign as class property.
    %       findCoolingPlateExtremes             - Find extreme positions of components and corners of the cooling plate.
    %       addThermalConnectionLabels           - Add connection labels for thermal port of blocks in flow network.
    %       assignDiscretePipeProperties         - Compute start and end positions, overlap length, and partition index for a discrete pipe element lying in a partition.
    %       assignDiscreteBendProperties         - Compute start and end positions, overlap length, and partition index for a discrete bend element lying in a partition.
    %       setOrientationPipeSubsystem          - Set position and orientation of the subsystem representing a discrete pipe element.
    %       findUpstrmComponentOrientDirection   - Find orientation and direction of the component upstream or connected to port A of a component.
    %       setOrientationBendSubsystem          - Set position & orientation of the subsystem representing a discrete bend element.
    %       addPartitionAreas                    - Add area blocks for visual representation and segregation of partitions.
    %       setPosOrientationThermalConnLabels   - Set position and orientation of connection labels for thermal port of blocks.
    %       connectFlowComponents                - Connect blocks for discrete elements in flow network subsystem.
    %       computeFluidInPortPosition           - Compute position and orientation of fluid inport of flow network subsystem.
    %       computeFluidOutPortPosition          - Compute position and orientation of fluid outport of flow network subsystem.
    %       connectFlowToThermalArray            - Connect flow network subsystem and thermal network component with array connection for battery nodes.
    %       createMaskFlowSystem                 - Create mask for the flow network subsystem.
    %       createMaskCoolingPlate               - Create mask for the cooling plate subsystem.
    %       createMaskIconCoolingPlate           - Create mask icon for the cooling plate subsystem.
    %       setFlowParametersInModel             - Set block parameters in flow network subsystem.
    %       setThermalParametersInModel          - Set parameters in Simscape Component for thermal network.
    %       setMaterialPropertiesInModel         - Set cooling plate material properties in model.
    %       setArrayConnParametersInModel        - Set block parameters of array connection which connects cooling plate and battery modules.
    %       saveCoolingPlateLib                  - Save cooling plate masked subsystem in a locked library
    %       storeMaterialProp                    - Store cooling plate material properties in a structure.
    %       verifyArraySizeThermalNodes          - Verify array size of dimensionThermalNodes and locationThermalNodes parameters for battery modules.
    %       createEmptySubsystem                 - Create an empty subsystem.
    %       verifyComponentsInsidePlate          - Verify whether all components lie inside a rectangular plate.
    %       verifyNodesInsidePlate               - Verify whether a point lies inside a rectangular plate.
    %       findCanvasScaling                    - Find canvas scaling for flow network subsystem based on positions of discrete pipe elements.
    %       findBlockPositionFromCADPosition     - Find block position from CAD component position.
    %       assignOrientationPipe                - Assign pipe orientation as either horizontal or vertical.
    %       assignDirectionPipe                  - Assign pipe direction as up, down, left or right.
    %       assignOrientationBend                - Assign bend orientation.
    %       findLineRectangleOverlap             - Find the overlap between a line segment and a rectangle.
    %       findArcRectangleOverlap              - Find the overlap between a arc segment and a rectangle.
    %       intersectSegments                    - Determine the intersection point of two line segments, if any.
    %       isPointInPolygon                     - Determine points located inside or on edge of a polygon.

    % Copyright 2025 - 2026 The MathWorks, Inc.

    properties (Constant)
        ModelName                      = "BatteryCoolingPlate"
        CoolingPlateSystem             = "BatteryCoolingPlate/Cooling Plate"
        FlowSystem                     = "BatteryCoolingPlate/Cooling Plate/Flow Network"
        FlowSystemBusBlock             = "BatteryCoolingPlate/Cooling Plate/Flow Network/SimscapeBus"
        FlowSystemThermalArrayConn     = "BatteryCoolingPlate/Cooling Plate/Flow Network/Array Connection";
        LibBlockCoolingPlateThermal    = "coolingPlateThermal_lib/Cooling Plate Connector";
        CoolingPlateThermalComponent   = "BatteryCoolingPlate/Cooling Plate/Cooling Plate Connector";
        CoolingPlateToBatteryArrayConn = "BatteryCoolingPlate/Array Connection";
        FlowSystemXRef                 = 100;
        FlowSystemYRef                 = 100;
    end

    properties
        ConnectivityData
        MaterialProp
        AllComponents
        NumComponents
        Component
        Plate
        DiscreteElement
        Partition
        Canvas
        DiscreteElemPartition
        Mask
    end

    methods
        %% Constructor of ComponentConnectivity class
        function obj = ComponentConnectivity(ConnectivityData,numBattThermalNodes,dimensionThermalNodes,...
                locationThermalNodes,options)
        % Creates a ComponentConnectivity object that maps a cooling channel
        % network to battery thermal nodes and a cooling plate.

        %
        %   Inputs:
        %       ConnectivityData        - Structure defining the cooling channel
        %                                 flow network connectivity.
        %       numBattThermalNodes     - Total number of battery thermal nodes.
        %       dimensionThermalNodes  - [N x 2] array of thermal node dimensions.
        %       locationThermalNodes   - [N x 2] array of XY locations of battery
        %                                 thermal nodes on the cooling plate.
        %
        %   Optional name-value inputs (options):
        %       numPartitionsX            - Number of partitions in X direction of cooling plate
        %       numPartitionsY            - Number of partitions in Y direction of cooling plate
        %       thicknessPlate            - Thickness of plate
        %       thermalConductivityPlate  - Thermal conductivity of plate material
        %       densityPlate              - Density of plate material
        %       specificHeatPlate         - Specific heat of plate material
        %       initialTemperaturePlate   - Initial temperature of plate
        %
        %   Output:
        %       obj - ComponentConnectivity object containing thermal connectivity
        %             and cooling plate geometry & material property data.
        %
        %   Note: The plate is discretized uniformly based on numPartitionsX and
        %         numPartitionsY.

            arguments (Input)
                ConnectivityData struct
                numBattThermalNodes (1,1) {mustBeInteger}
                dimensionThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(dimensionThermalNodes, 'm')}
                locationThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(locationThermalNodes, 'm')}
                options.numPartitionsX (1,1) {mustBeInteger} = 5;
                options.numPartitionsY (1,1) {mustBeInteger} = 6;
                options.thicknessPlate = simscape.Value(2e-3,"m");
                options.thermalConductivityPlate = simscape.Value(20,"W/(K*m)");
                options.densityPlate = simscape.Value(2700,"kg/m^3");
                options.specificHeatPlate = simscape.Value(447,"J/(K*kg)");
                options.initialTemperaturePlate = simscape.Value(293.15,"K");
            end

            arguments (Output)
                obj ComponentConnectivity
            end

            obj.ConnectivityData = ConnectivityData;

            % Assign cooling plate material properties
            obj.MaterialProp = ComponentConnectivity.storeMaterialProp(options.thicknessPlate,options.thermalConductivityPlate,...
                options.densityPlate,options.specificHeatPlate,options.initialTemperaturePlate);

            % Create and open a new model
            if bdIsLoaded(obj.ModelName)
                close_system(obj.ModelName,0);
                new_system(obj.ModelName);
            else
                new_system(obj.ModelName);
            end
            open_system(obj.ModelName);

            % Verify size of dimensionThermalNodes and locationThermalNodes
            ComponentConnectivity.verifyArraySizeThermalNodes(numBattThermalNodes,dimensionThermalNodes,...
                locationThermalNodes)

            % Create cooling plate subsystem
            coolingPlateSystemPosition = [200 50 350 200];
            ComponentConnectivity.createEmptySubsystem(obj.CoolingPlateSystem,coolingPlateSystemPosition);

            % Create flow network subsystem
            flowSystemPosition = [250 80 345 190];
            ComponentConnectivity.createEmptySubsystem(obj.FlowSystem,flowSystemPosition);

            % Add blocks in flow network subsystem
            obj = obj.addFlowComponentsInModel(options.numPartitionsX,options.numPartitionsY);

            % Connect blocks in flow network subsystem
            obj.connectFlowComponents;

            % Create a mask for the flow network subsystem
            obj = obj.createMaskFlowSystem;

            % Add Simscape Component that represents thermal network
            obj = obj.addThermalComponentInModel;

            % Connect flow network with thermal network and array
            % connection
            obj.connectFlowToThermalArray;

            % Create a mask for the cooling plate subsystem
            obj = obj.createMaskCoolingPlate;

            % Set parameters in flow network subsystem
            obj.setFlowParametersInModel;

            % Set parameters in Simscape component for thermal network
            obj.setThermalParametersInModel(numBattThermalNodes,dimensionThermalNodes,...
                locationThermalNodes,options.numPartitionsX,options.numPartitionsY);

            % Set parameters in array connection between cooling plate and
            % battery modules
            obj.setArrayConnParametersInModel(numBattThermalNodes);

            % Set model canvas zoom factor to 100
            set_param(gcs, 'ZoomFactor', '100');

            % Save model as library in Components folder
            obj.saveCoolingPlateLib;

        end

        %% ADD FLOW NETWORK BLOCKS IN THE MODEL
        function obj = addFlowComponentsInModel(obj,numPartitionsX,numPartitionsY)
        % Add blocks for the flow network components in the model
            arguments
                obj ComponentConnectivity
                numPartitionsX (1,1) {mustBeInteger}
                numPartitionsY (1,1) {mustBeInteger}
            end

            obj.NumComponents = numel(obj.ConnectivityData);
            obj.AllComponents.Names = [];

            obj.Canvas.PipeBlockSize = [100 67];  % [width, height] in Simulink canvas units
            obj.Canvas.BendSystemSize = [60 60];

            % Store all positions and centerline points in SI unit (m)
            obj = assignPositionsInSIUnit(obj);

            % Find extremes of components and corners of the cooling plate
            obj = findCoolingPlateExtremes(obj);

            % Verify whether components lie inside the cooling plate
            ComponentConnectivity.verifyComponentsInsidePlate(obj);

            % Compute partition sizes
            obj.Plate.PartitionWidth = (obj.Plate.xMaxPlate - obj.Plate.xMinPlate) / numPartitionsX;
            obj.Plate.PartitionHeight = (obj.Plate.yMaxPlate - obj.Plate.yMinPlate) / numPartitionsY;

            for iComp = 1:obj.NumComponents

                for iPartX = 1:numPartitionsX
                    for iPartY = 1:numPartitionsY

                        % Compute vertices of partitions
                        x1Part = obj.Plate.xMinPlate + (iPartX - 1)*obj.Plate.PartitionWidth;
                        x2Part = x1Part + obj.Plate.PartitionWidth;
                        y1Part = obj.Plate.yMinPlate + (iPartY - 1)*obj.Plate.PartitionHeight;
                        y2Part = y1Part + obj.Plate.PartitionHeight;
                        obj.Partition(iPartX,iPartY).Position = [x1Part y1Part x2Part y2Part];
                        obj.Partition(iPartX,iPartY).Corners = [x1Part y1Part; x2Part y1Part; x2Part y2Part; x1Part y2Part];

                        % Determine index of discrete pipe or bend element that lies in a rectangular partition
                        if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                            obj = assignDiscretePipeProperties(obj, iComp, iPartX, iPartY);
                        elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                            obj = assignDiscreteBendProperties(obj, iComp, iPartX, iPartY);
                        end

                    end
                end

                % Find the sum of non-empty fields of the struct
                % obj.DiscreteElement & assign as sum of number of discrete elements
                obj.Component(iComp).NumDiscretize = ...
                    sum(arrayfun(@(s) any(structfun(@(f) ~isempty(f),s)),obj.DiscreteElement(iComp,:)));
            end

            % Determine canvas size, scaling required in X & Y directions
            % for adequate block spacing based on pipe positions

            padding = 400; % Padding for model canvas around component blocks
            [~, ~, scaleX, scaleY] = ComponentConnectivity.findCanvasScaling(obj,padding);
            obj.Canvas.ScaleX = scaleX; obj.Canvas.ScaleY = scaleY;

            % Specify library path of required blocks
            subsysRefLibPath = "simulink/Ports & Subsystems/Subsystem Reference";
            arrayConnLibPath = "nesl_utility/Array Connection";
            connLabelLibPath = "nesl_utility/Connection Label";

            % Add Array Connection block and set domain for flow network to
            % thermal network connection
            add_block(arrayConnLibPath, obj.FlowSystemThermalArrayConn, "Position", ...
                [obj.FlowSystemXRef-200, obj.FlowSystemYRef-160, ...
                obj.FlowSystemXRef-120, obj.FlowSystemYRef+140]);
            set_param(obj.FlowSystemThermalArrayConn,"Domain","foundation.thermal.thermal");

            % Add Array Connection block and set domain for cooling plate
            % to battery connection
            add_block(arrayConnLibPath, obj.CoolingPlateToBatteryArrayConn, "Position", [100, 5, 135, 60]);
            set_param(obj.CoolingPlateToBatteryArrayConn,"Domain","foundation.thermal.thermal");

            % Initialize
            blockCount = 0;

            for iComp=1:obj.NumComponents
                % Find orientation of components
                if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)

                    % Determine pipe orientation
                    obj.Component(iComp).Orientation = ComponentConnectivity.assignOrientationPipe(obj.Component(iComp).Position);

                    % Determine pipe direction
                    obj.Component(iComp).Direction = ComponentConnectivity.assignDirectionPipe(obj.Component(iComp).Position,...
                        obj.Component(iComp).Orientation);

                    % Assign block size
                    blockSize = obj.Canvas.PipeBlockSize;

                elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)

                    % Determine bend orientation
                    obj.Component(iComp).Orientation = ComponentConnectivity.assignOrientationBend(obj.Component(iComp).Position);

                    % Assign bend subsystem size
                    blockSize = obj.Canvas.BendSystemSize;

                end

                % Add, position & orient blocks
                for iDisc=1:obj.Component(iComp).NumDiscretize
                    blockCount = blockCount + 1;

                    pos = obj.DiscreteElement(iComp, iDisc).Position;

                    % Find block position on Simulink canvas based on
                    % mapping with actual position

                    blockPosition = ComponentConnectivity.findBlockPositionFromCADPosition(pos,obj.AllComponents.XMin,...
                        obj.AllComponents.YMax,padding,scaleX,scaleY,blockSize);
                    obj.DiscreteElement(iComp,iDisc).BlockPosition = blockPosition;

                    if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                        % Add pipe block
                        pipeSysPath = strcat(obj.FlowSystem,"/",obj.ConnectivityData(iComp).Component,"_",string(iDisc));
                        % Add the Subsystem Reference block
                        add_block(subsysRefLibPath, pipeSysPath, "ReferencedSubsystem", "PipeSubsystemWithMask","Position",blockPosition);
                    elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                        % Add subsystem and equivalent pipe for a bend
                        bendSysPath = strcat(obj.FlowSystem,"/",obj.ConnectivityData(iComp).Component,"_",string(iDisc));
                        add_block(subsysRefLibPath, bendSysPath, "ReferencedSubsystem", "BendSubsystemWithMask","Position",blockPosition);
                        obj.DiscreteElement(iComp,iDisc).BlockHandlesEqPipe = getSimulinkBlockHandle(strcat(bendSysPath,"/Equivalent Pipe"));
                    end

                    obj.DiscreteElement(iComp,iDisc).BlockHandlesFlow = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",...
                        obj.ConnectivityData(iComp).Component,"_",string(iDisc)));

                    % Set orientation of pipes and bend subsystems
                    if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                        setOrientationPipeSubsystem(obj,pipeSysPath,iComp);
                        set_param(pipeSysPath,"directionPipe",obj.Component(iComp).Direction);
                    elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                        setOrientationBendSubsystem(obj,bendSysPath,iComp);
                    end

                    % Add connection labels for thermal port
                    obj = addThermalConnectionLabels(obj, connLabelLibPath, iComp, iDisc);

                    % Set position & orientation of connection labels
                    setPosOrientationThermalConnLabels(obj, iComp, iDisc, blockCount);

                    % Assign thermal array port name for each discrete element
                    obj.DiscreteElement(iComp,iDisc).ThermalArrayPort = strcat("elementNode",string(blockCount));

                    % Assign partition indices for each discrete element to array
                    partitionArrayNew = obj.DiscreteElement(iComp,iDisc).Partition;
                    obj.DiscreteElemPartition(end+1,:) = partitionArrayNew;

                end

            end

            % Set number of scalar elements of array connection to number
            % of discretized elements
            set_param(obj.FlowSystemThermalArrayConn,"NumScalarElements",string(blockCount));

            % Add area blocks for visual representation of partitions
            addPartitionAreas(obj,numPartitionsX,numPartitionsY,scaleX,scaleY,padding);

        end

        %% ADD THERMAL NETWORK IN THE MODEL
        function obj = addThermalComponentInModel(obj)
        % Add Simscape Component for the thermal network in the model
        arguments
            obj ComponentConnectivity
        end

            % Navigate to Components folder under project root
            prjRoot = currentProject().RootFolder;
            componentsFolder = fullfile(prjRoot, 'Components');
            cd (componentsFolder);

            % Suppress Library Browser warning
            warnState = warning("off", "sl_lib_browse2:sl_lib_browse2:SLLB_ReposNotSupportedNoDisplay");
            cleanupObj = onCleanup(@() warning(warnState));

            % Compile ssc file for thermal network into a library
            sscbuild coolingPlateThermal;

            % Add Simscape Component in model canvas
            blockCoolingPlateThermalPosition = [100, 145, 200, 245];
            add_block(obj.LibBlockCoolingPlateThermal, obj.CoolingPlateThermalComponent, ...
                "Position", blockCoolingPlateThermalPosition);
            cd ..

        end

        function obj = assignPositionsInSIUnit(obj)
        % Convert and store component positions and centerline coordinates 
        % in SI unit and assign as class property
        arguments
            obj ComponentConnectivity
        end

            position = simscape.Value(zeros(obj.NumComponents,4),"m");
            x1 = zeros(obj.NumComponents,1); y1 = zeros(obj.NumComponents,1);
            x2 = zeros(obj.NumComponents,1); y2 = zeros(obj.NumComponents,1);

            for iComp=1:obj.NumComponents
                component = obj.ConnectivityData(iComp).Component;
                obj.AllComponents.Names = [obj.AllComponents.Names, component];

                position(iComp,:) = convert(obj.ConnectivityData(iComp).Parameters.position,"m");

                x1(iComp)= position(iComp,1).value;
                y1(iComp)= position(iComp,2).value;
                x2(iComp)= position(iComp,3).value;
                y2(iComp)= position(iComp,4).value;
                obj.Component(iComp).Position = [x1(iComp) y1(iComp) x2(iComp) y2(iComp)];

                if contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                    centerlinePts = convert(obj.ConnectivityData(iComp).Parameters.centerlinePts,"m");
                    obj.Component(iComp).CenterlinePts = centerlinePts.value;
                end

            end

        end

        function obj = findCoolingPlateExtremes(obj)
        % Find extreme positions of components and corners of the cooling plate
        arguments
            obj ComponentConnectivity
        end

            position = zeros(obj.NumComponents,4);
            xAll = [];
            yAll = [];

            for iComp = 1:obj.NumComponents

                % Straight component endpoints
                position(iComp,:) = obj.Component(iComp).Position;
                xAll = [xAll; position(iComp,1); position(iComp,3)];
                yAll = [yAll; position(iComp,2); position(iComp,4)];

                % Bend centerline points (if present)
                if contains(obj.ConnectivityData(iComp).Component, "bend", "IgnoreCase", true)
                    centerlinePtsVal = convert( ...
                        obj.ConnectivityData(iComp).Parameters.centerlinePts, "m");
                    centerlinePtsVal = centerlinePtsVal.value;

                    xAll = [xAll; centerlinePtsVal(:,1)];
                    yAll = [yAll; centerlinePtsVal(:,2)];
                end
            end

            % Find true global bounds
            obj.AllComponents.XMin = min(xAll);
            obj.AllComponents.XMax = max(xAll);
            obj.AllComponents.YMin = min(yAll);
            obj.AllComponents.YMax = max(yAll);

            % Find number of horizontal and vertical levels
            isHorizontal = abs(position(:,4) - position(:,2))./abs(position(:,3) - position(:,1)) <= 1;
            isVertical = abs(position(:,4) - position(:,2))./abs(position(:,3) - position(:,1)) > 1;

            horizontalLevels = unique(position(isHorizontal, 2));
            verticalLevels = unique(position(isVertical, 1));

            numHorizontalLevels = numel(horizontalLevels);
            numVerticalLevels = numel(verticalLevels);

            % Estimate component spacing
            if numVerticalLevels>1
                compSpacingX = (obj.AllComponents.XMax - obj.AllComponents.XMin)/(numVerticalLevels - 1);
            else
                compSpacingX = 0.5*(obj.AllComponents.XMax - obj.AllComponents.XMin);
            end
            if numHorizontalLevels>1
                compSpacingY = (obj.AllComponents.YMax - obj.AllComponents.YMin)/(numHorizontalLevels - 1);
            else
                compSpacingY = 0.5*(obj.AllComponents.YMax - obj.AllComponents.YMin);
            end

            edgeSpacing = min(0.25*compSpacingX, 0.25*compSpacingY);

            % Compute plate boundaries (add half spacing on each side)
            obj.Plate.xMinPlate = obj.AllComponents.XMin - edgeSpacing;
            obj.Plate.xMaxPlate = obj.AllComponents.XMax + edgeSpacing;
            obj.Plate.yMinPlate = obj.AllComponents.YMin - edgeSpacing;
            obj.Plate.yMaxPlate = obj.AllComponents.YMax + edgeSpacing;

        end

        function obj = addThermalConnectionLabels(obj, connLabelLibPath, iComp, iDisc)
         % Add connection labels for thermal port of blocks in flow network
         arguments
             obj ComponentConnectivity
             connLabelLibPath (1,1) string
             iComp (1,1) {mustBeInteger}
             iDisc (1,1) {mustBeInteger}
         end

            add_block(connLabelLibPath,strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)));
            obj.DiscreteElement(iComp,iDisc).ConnLabelHandles = ...
                getSimulinkBlockHandle(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)));
            set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                "Label",strcat("H_",string(iComp),"_",string(iDisc)),"ShowName","off");

            add_block(connLabelLibPath,strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc),"_bus"));
            obj.DiscreteElement(iComp,iDisc).BusConnLabelHandles = ...
                getSimulinkBlockHandle(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc),"_bus"));
            set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc),"_bus"),...
                "Label",strcat("H_",string(iComp),"_",string(iDisc)),"ShowName","off");

        end

        function obj = assignDiscretePipeProperties(obj, iComp, iPartX, iPartY)
        % Compute start and end positions, overlap length, and partition 
        % index for a discrete pipe element lying in a partition
        arguments
             obj ComponentConnectivity
             iComp (1,1) {mustBeInteger}
             iPartX (1,1) {mustBeInteger}
             iPartY (1,1) {mustBeInteger}
        end

            position(iComp,:) = obj.Component(iComp).Position;
            x1(iComp)= position(iComp,1);
            y1(iComp)= position(iComp,2);
            x2(iComp)= position(iComp,3);
            y2(iComp)= position(iComp,4);

            [overlapLen(iComp,iPartX,iPartY), discreteElemPtsInPart] = ...
                ComponentConnectivity.findLineRectangleOverlap(obj.Partition(iPartX,iPartY).Corners,[x1(iComp) y1(iComp)], [x2(iComp) y2(iComp)]);

            % Find pipe orientation and select reference partition length to determine discrete element index
            pipeStartEndPts(iComp,:) = [x1(iComp) y1(iComp) x2(iComp) y2(iComp)];
            orientation(iComp) = ComponentConnectivity.assignOrientationPipe(pipeStartEndPts(iComp,:));
            obj.Component(iComp).Orientation = orientation(iComp);

            if strcmpi(obj.Component(iComp).Orientation,"horizontal")
                partLength = obj.Plate.PartitionWidth;
            else
                partLength = obj.Plate.PartitionHeight;
            end

            if overlapLen(iComp,iPartX,iPartY) > 0.001 %% discrete element length must be more than 0.001 m
                startPipe = [x1(iComp) y1(iComp)];
                endDiscreteElem = [discreteElemPtsInPart(2,1) discreteElemPtsInPart(2,2)];
                distFromPipeStart = norm(endDiscreteElem - startPipe);

                % discrete element length must be more than 0.001 m
                iDisc = ceil((distFromPipeStart - overlapLen(iComp,iPartX,iPartY) - 0.001)/partLength) + 1;

                % Assign discrete element positions, length and partitions as properties
                obj.DiscreteElement(iComp,iDisc).Position = ...
                    [discreteElemPtsInPart(1,1) discreteElemPtsInPart(1,2) discreteElemPtsInPart(end,1) discreteElemPtsInPart(end,2)];
                obj.DiscreteElement(iComp,iDisc).Length = overlapLen(iComp,iPartX,iPartY);
                obj.DiscreteElement(iComp,iDisc).Partition = [iPartX iPartY];
            end

        end

        function obj = assignDiscreteBendProperties(obj, iComp, iPartX, iPartY)
        % Compute start and end positions, overlap length, and partition 
        % index for a discrete bend element lying in a partition
        arguments
             obj ComponentConnectivity
             iComp (1,1) {mustBeInteger}
             iPartX (1,1) {mustBeInteger}
             iPartY (1,1) {mustBeInteger}
        end

            % Bend points
            bendPts = obj.Component(iComp).CenterlinePts;

            % Determine overlap length with a rectangular partition
            partitionCorners = obj.Partition(iPartX,iPartY).Corners;
            [bendOverlapLen(iComp,iPartX,iPartY), bendPtsInRect] = ComponentConnectivity.findArcRectangleOverlap(partitionCorners, bendPts);

            if bendOverlapLen(iComp,iPartX,iPartY) > 0.001 && size(bendPtsInRect, 1) >= 2
                % Compute full cumulative arc length
                dBend = vecnorm(diff(bendPts, 1, 1), 2, 2); % pairwise distances
                bendLengthFromStart = [0; cumsum(dBend)];   % cumulative length at each point

                % Find the first point of bendPtsInRect in bendPts
                [~, startIdx] = ismember(bendPtsInRect(1,:), bendPts, 'rows');
                if startIdx == 0
                    % If not exactly found, find nearest point
                    dists = vecnorm(bendPts - bendPtsInRect(1,:), 2, 2);
                    [~, startIdx] = min(dists);
                end

                % Distance from bend start to partition entry point (along arc)
                bendStartToPartition = bendLengthFromStart(startIdx);

                % Choose part length based on partition shape
                if obj.Plate.PartitionWidth < obj.Plate.PartitionHeight
                    partLength = obj.Plate.PartitionWidth;
                else
                    partLength = obj.Plate.PartitionHeight;
                end

                % Determine discrete index
                iDisc = ceil((bendStartToPartition - 0.001) / partLength) + 1;

                % Assign discrete element positions, length and partitions as properties
                obj.DiscreteElement(iComp,iDisc).Position = ...
                    [bendPtsInRect(1,1) bendPtsInRect(1,2) bendPtsInRect(end,1) bendPtsInRect(end,2)];
                obj.DiscreteElement(iComp,iDisc).Length = bendOverlapLen(iComp,iPartX,iPartY);
                obj.DiscreteElement(iComp,iDisc).Partition = [iPartX iPartY];
            end

        end
       
        function setOrientationPipeSubsystem(obj,pipeBlockPath,iComp)
        % Set position and orientation of the subsystem representing a discrete pipe element
        arguments
             obj ComponentConnectivity
             pipeBlockPath (1,1) string
             iComp (1,1) {mustBeInteger}
        end

            if strcmpi(obj.Component(iComp).Orientation,"horizontal") && strcmpi(obj.Component(iComp).Direction,"left")
                set_param(pipeBlockPath,"BlockRotation",180);
            elseif strcmpi(obj.Component(iComp).Orientation,"vertical") && strcmpi(obj.Component(iComp).Direction,"up")
                set_param(pipeBlockPath,"BlockRotation",-90);
            elseif strcmpi(obj.Component(iComp).Orientation,"vertical") && strcmpi(obj.Component(iComp).Direction,"down")
                set_param(pipeBlockPath,"BlockRotation",90);
            end

        end
        
        function [orientUpstreamComp,dirUpstreamComp] = findUpstrmComponentOrientDirection(obj,iComp)
        % Find orientation and direction of the component upstream or 
        % connected to port A of a component
        arguments (Input)
             obj ComponentConnectivity
             iComp (1,1) {mustBeInteger}
        end

        arguments (Output)
            orientUpstreamComp (1,1) string
            dirUpstreamComp (1,1) string
        end

            portAConnectedComponent = obj.ConnectivityData(iComp).Connectivity.portAConnectedComponent;
            indexUpstream = find(obj.AllComponents.Names == portAConnectedComponent);
            orientUpstreamComp = obj.Component(indexUpstream).Orientation;
            dirUpstreamComp = obj.Component(indexUpstream).Direction;

        end
       
        function setOrientationBendSubsystem(obj,bendSubsystemPath,iComp)
        % Set position & orientation of the subsystem representing a discrete bend element
        arguments
             obj ComponentConnectivity
             bendSubsystemPath (1,1) string
             iComp (1,1) {mustBeInteger}
        end

            % Find bend orientation
            bendOrient = ComponentConnectivity.assignOrientationBend(obj.Component(iComp).Position);
            if strcmp(bendOrient,"invalid")
                error(strcat("Position for ",obj.ConnectivityData(iComp).Component," is invalid."));
            end

            % Find upstream pipe orientation
            [~,dirUpstreamPipe] = findUpstrmComponentOrientDirection(obj,iComp);

            % Rotate bend subsystem as per bend orientation and upstream pipe orientation
            if strcmp(dirUpstreamPipe,"up") && contains(bendOrient,"right")
                set_param(bendSubsystemPath,"Orientation","down","BlockRotation",90);
            elseif strcmp(dirUpstreamPipe,"up") && contains(bendOrient,"left")
                set_param(bendSubsystemPath,"Orientation","up");
            elseif strcmp(dirUpstreamPipe,"down") && contains(bendOrient,"right")
                set_param(bendSubsystemPath,"BlockRotation",90);
            elseif strcmp(dirUpstreamPipe,"down") && contains(bendOrient,"left")
                set_param(bendSubsystemPath,"Orientation","down");
            elseif strcmp(dirUpstreamPipe,"right") && contains(bendOrient,"up")
                set_param(bendSubsystemPath,"Orientation","right");
            elseif strcmp(dirUpstreamPipe,"right") && contains(bendOrient,"down")
                set_param(bendSubsystemPath,"Orientation","down","BlockRotation",180);
            elseif strcmp(dirUpstreamPipe,"left") && contains(bendOrient,"up")
                set_param(bendSubsystemPath,"Orientation","left");
            elseif strcmp(dirUpstreamPipe,"left") && contains(bendOrient,"down")
                set_param(bendSubsystemPath,"BlockRotation",180);
            end

        end
  
        function addPartitionAreas(obj,numPartitionsX,numPartitionsY,scaleX,scaleY,padding)
        % Add area blocks for visual representation and segregation of partitions
        arguments
            obj ComponentConnectivity
            numPartitionsX (1,1) {mustBeInteger}
            numPartitionsY (1,1) {mustBeInteger}
            scaleX (1,1) double
            scaleY (1,1) double
            padding (1,1) double = 400;
        end

            for iPartX = 1:numPartitionsX
                for iPartY = 1:numPartitionsY

                    partitionPos = obj.Partition(iPartX,iPartY).Position;
                    partitionCanvasWid = scaleX*(partitionPos(3) - partitionPos(1));
                    partitionCanvasHt = scaleY*(partitionPos(4) - partitionPos(2));

                    partitionCanvasPos = ComponentConnectivity.findBlockPositionFromCADPosition(partitionPos,...
                        obj.AllComponents.XMin,obj.AllComponents.YMax,padding,scaleX,scaleY,[partitionCanvasWid partitionCanvasHt]);
                    key = sprintf('%d_%d', iPartX, iPartY);

                    areaName = ['Partition_' key];
                    add_block('built-in/Area', strcat(obj.FlowSystem,"/",areaName),'Position',partitionCanvasPos);
                    areaColor = [0.98 0.98 1 0.5];
                    set_param(strcat(obj.FlowSystem,"/",areaName),'Name',['Partition [' strrep(key, '_', ',') ']'],...
                        'BackgroundColor', mat2str(areaColor));

                end
            end

        end
       
        function setPosOrientationThermalConnLabels(obj, iComp, iDisc, blockCount)
        % Set position and orientation of connection labels for thermal port of discrete element blocks
        arguments
            obj ComponentConnectivity
            iComp {mustBeInteger}
            iDisc {mustBeInteger}
            blockCount {mustBeInteger}
        end

            blockPosition = obj.DiscreteElement(iComp,iDisc).BlockPosition;

            x1Block = blockPosition(1); y1Block = blockPosition(2);
            x2Block = blockPosition(1); y2Block = blockPosition(2);

            if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                % Set position & orientation of connection label for discrete pipe element
                if strcmpi(obj.Component(iComp).Orientation,"horizontal") && strcmpi(obj.Component(iComp).Direction,"right")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x1Block+40 y1Block-40 x1Block+60 y1Block-20],"Orientation","up");
                elseif strcmpi(obj.Component(iComp).Orientation,"horizontal") && strcmpi(obj.Component(iComp).Direction,"left")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x1Block+40 y2Block+90 x1Block+60 y2Block+110],"Orientation","down");
                elseif strcmpi(obj.Component(iComp).Orientation,"vertical") && strcmpi(obj.Component(iComp).Direction,"up")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x1Block-30 y1Block+20 x1Block-10 y1Block+40],"Orientation","left");
                elseif strcmpi(obj.Component(iComp).Orientation,"vertical") && strcmpi(obj.Component(iComp).Direction,"down")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x2Block+90 y1Block+15 x2Block+110 y1Block+35],"Orientation","right");
                end

            elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                % Set position & orientation of connection label for discrete bend element

                % Find upstream pipe orientation
                upstreamPipeOrient = findUpstrmComponentOrientDirection(obj,iComp);

                % Rotate connection label as per bend orientation and upstream pipe orientation
                if strcmp(upstreamPipeOrient,"vertical") && contains(obj.Component(iComp).Orientation,"right")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x1Block-40 y1Block+35 x1Block-20 y1Block+55],"Orientation","left");
                elseif strcmp(upstreamPipeOrient,"vertical") && contains(obj.Component(iComp).Orientation,"left")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x2Block+80 y1Block+35 x2Block+100 y1Block+55],"Orientation","right");
                elseif strcmp(upstreamPipeOrient,"horizontal") && contains(obj.Component(iComp).Orientation,"up")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x2Block+35 y2Block+95 x2Block+55 y2Block+115],"Orientation","down");
                elseif strcmp(upstreamPipeOrient,"horizontal") && contains(obj.Component(iComp).Orientation,"down")
                    set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc)),...
                        "Position",[x1Block+25 y1Block-50 x1Block+45 y1Block-30],"Orientation","up");
                end

            end

            y1ConnLabel = obj.FlowSystemYRef - 200 + blockCount*40;
            set_param(strcat(obj.FlowSystem,"/H_",string(iComp),"_",string(iDisc),"_bus"),...
                "Position",[obj.FlowSystemXRef-300 y1ConnLabel obj.FlowSystemXRef-280 y1ConnLabel+20],"Orientation","left");

        end

        %% CONNECT FLOW COMPONENTS
        function connectFlowComponents(obj)
        % Connect blocks for discrete elements in flow network subsystem
            arguments
                obj ComponentConnectivity
            end

            for iComp = 1:obj.NumComponents

                % if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                % Connect the discretized blocks for each pipe
                for iDisc = 1:obj.Component(iComp).NumDiscretize-1
                    simscape.addConnection(obj.DiscreteElement(iComp,iDisc).BlockHandlesFlow,"B",...
                        obj.DiscreteElement(iComp,iDisc+1).BlockHandlesFlow,"A","autorouting","smart");
                end

                % Connect the thermal port of discretized blocks with connection labels
                for iDisc = 1:obj.Component(iComp).NumDiscretize
                    simscape.addConnection(obj.DiscreteElement(iComp,iDisc).BlockHandlesFlow,"H",...
                        obj.DiscreteElement(iComp,iDisc).ConnLabelHandles,"port","autorouting","smart");

                    % Connect connection labels to Thermal Array Connection
                    simscape.addConnection(obj.DiscreteElement(iComp,iDisc).BusConnLabelHandles,"port",...
                        obj.FlowSystemThermalArrayConn,obj.DiscreteElement(iComp,iDisc).ThermalArrayPort,"autorouting","smart");
                end
                % end

                % Connect the components as per connectivity data
                portA = obj.ConnectivityData(iComp).Connectivity.portAName;
                portAConnectedComponent = obj.ConnectivityData(iComp).Connectivity.portAConnectedComponent;
                portB = obj.ConnectivityData(iComp).Connectivity.portBName;
                portBConnectedComponent = obj.ConnectivityData(iComp).Connectivity.portBConnectedComponent;

                connPortLibPath = "nesl_utility/Connection Port";

                fluidInPortFlowSystem = strcat(obj.FlowSystem,"/fluid_in");
                fluidOutPortFlowSystem = strcat(obj.FlowSystem,"/fluid_out");

                % If port B of component connected to Sink, then add fluid_out port, find
                % out block position to be connected to fluid_out port
                % & position fluid_out port accordingly
                if strcmpi(portBConnectedComponent,"Sink")
                    outFlowPortHandle = getSimulinkBlockHandle(fluidOutPortFlowSystem);
                    if outFlowPortHandle == -1
                        add_block(connPortLibPath,fluidOutPortFlowSystem);
                        % Assign position of fluid_in port
                        [outFlowPortPos,outFlowPortOrient] = computeFluidOutPortPosition(obj);
                        % Set position
                        set_param(fluidOutPortFlowSystem,"Position",outFlowPortPos);
                        set_param(fluidOutPortFlowSystem,"Orientation",outFlowPortOrient);
                    end

                    portBConnectedBlock = getSimulinkBlockHandle(fluidOutPortFlowSystem);
                    portBConnectedPort = "port";
                else
                    portBConnectedPort = obj.ConnectivityData(iComp).Connectivity.portBConnectedPort;
                    % Find the index of pipe component connected to port B
                    indexDownstream = find(obj.AllComponents.Names == portBConnectedComponent);
                    if strcmp(portBConnectedPort,"A")
                        portBConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portBConnectedComponent,"_1")); % for pipe-portB connected to port A of connected component
                    elseif strcmp(portBConnectedPort,"B")
                        portBConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portBConnectedComponent,"_",...
                            string(obj.Component(indexDownstream).NumDiscretize)));  % if port B is connected to port B of connected component
                    else
                        portBConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portBConnectedComponent)); % for bend-portB connected block
                    end
                end

                % Get line connected to the upstream port
                BPortHandles = get_param(obj.DiscreteElement(iComp,obj.Component(iComp).NumDiscretize).BlockHandlesFlow, 'PortHandles');
                if strcmp(portB,"A")
                    portBHandle = BPortHandles.LConn(1);
                else
                    portBHandle = BPortHandles.RConn(1);
                end

                % Get line connected to the downstream port
                portBConnectedBlockPortHandles = get_param(portBConnectedBlock, 'PortHandles');
                if strcmp(portBConnectedPort,"A")
                    portBConnectedPortHandle = portBConnectedBlockPortHandles.LConn(1);
                else
                    portBConnectedPortHandle = portBConnectedBlockPortHandles.RConn(1);
                end

                % Check if the upstream and downstream ports are already connected
                lineConnectedSrc = get_param(portBHandle, 'Line');
                lineConnectedDest = get_param(portBConnectedPortHandle, 'Line');
                if lineConnectedSrc ~= -1 && lineConnectedDest ~= -1
                else
                    simscape.addConnection(obj.DiscreteElement(iComp,obj.Component(iComp).NumDiscretize).BlockHandlesFlow,portB,...
                        portBConnectedBlock,portBConnectedPort,"autorouting","smart");
                end

                if strcmpi(portAConnectedComponent,"Source")
                    inFlowPortHandle = getSimulinkBlockHandle(fluidInPortFlowSystem);
                    if inFlowPortHandle == -1
                        % add connection port for fluid_in
                        add_block(connPortLibPath,fluidInPortFlowSystem);
                        % Assign position of fluid_in port
                        [inFlowPortPos,inFlowPortOrient] = computeFluidInPortPosition(obj);
                        % Set position
                        set_param(fluidInPortFlowSystem,"Position",inFlowPortPos);
                        set_param(fluidInPortFlowSystem,"Orientation",inFlowPortOrient);
                    end

                    portAConnectedBlock = getSimulinkBlockHandle(fluidInPortFlowSystem);
                    portAConnectedPort = "port";
                else
                    portAConnectedPort = obj.ConnectivityData(iComp).Connectivity.portAConnectedPort;
                    % Find the index of pipe component connected to port A
                    indexUpstream = find(obj.AllComponents.Names == portAConnectedComponent);
                    if strcmp(portAConnectedPort,"B")
                        % Assign the last discretized element of upstream pipe as the port A connected block
                        portAConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portAConnectedComponent,"_",...
                            string(obj.Component(indexUpstream).NumDiscretize)));
                    elseif strcmp(portAConnectedPort,"A")
                        portAConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portAConnectedComponent,"_1"));
                    else
                        portAConnectedBlock = getSimulinkBlockHandle(strcat(obj.FlowSystem,"/",portAConnectedComponent));
                    end

                end

                % Get line connected to the upstream port
                APortHandles = get_param(obj.DiscreteElement(iComp,1).BlockHandlesFlow, 'PortHandles');
                if strcmp(portA,"A")
                    portAHandle = APortHandles.LConn(1);
                else
                    portAHandle = APortHandles.RConn(1);
                end

                % Get line connected to the downstream port
                portAConnectedBlockPortHandles = get_param(portAConnectedBlock, 'PortHandles');
                if strcmp(portAConnectedPort,"A")
                    portAConnectedPortHandle = portAConnectedBlockPortHandles.LConn(1);
                else
                    portAConnectedPortHandle = portAConnectedBlockPortHandles.RConn(1);
                end

                % Check if the upstream and downstream ports are already connected
                lineConnectedSrc = get_param(portAHandle, 'Line');
                lineConnectedDest = get_param(portAConnectedPortHandle, 'Line');
                if lineConnectedSrc ~= -1 && lineConnectedDest ~= -1
                else
                    simscape.addConnection(obj.DiscreteElement(iComp,1).BlockHandlesFlow,...
                        portA,portAConnectedBlock,portAConnectedPort,"autorouting","smart");
                end

            end

            % Connect Simscape bus for thermal ports to connection port
            HPortFlowSystem = strcat(obj.FlowSystem, "/H");
            add_block(connPortLibPath,HPortFlowSystem,"Position",...
                [obj.FlowSystemXRef-60, obj.FlowSystemYRef-125, ...
                obj.FlowSystemXRef-30, obj.FlowSystemYRef-111]);
            simscape.addConnection(obj.FlowSystemThermalArrayConn,"arrayNode",HPortFlowSystem,"port","autorouting","smart");

            % Set fluid_in, fluid_out, H port locations on parent subsystem
            set_param(fluidInPortFlowSystem,"Port","1","Side","Left");
            set_param(fluidOutPortFlowSystem,"Port","2","Side","Right");
            set_param(HPortFlowSystem,"Orientation","Left","Port","3","Side","Left");

        end

        function [blockPositionFluidIn, blockOrientFluidIn] = computeFluidInPortPosition(obj)
        % Compute position and orientation of fluid inport of flow network subsystem
        arguments (Input)
            obj 
        end

        arguments (Output)
            blockPositionFluidIn (1,4) double
            blockOrientFluidIn (1,1) string
        end

            iCompSrcConnectedArray = [];
            lengthArray = [];
            connPortWidth = 30;
            connPortHeight = 16;

            for iComp = 1:obj.NumComponents
                % Find connected components with source
                if strcmpi(obj.ConnectivityData(iComp).Connectivity.portAConnectedComponent, "Source")

                    iCompSrcConnectedArray(end+1) =  iComp;

                    % Find the lengths of connected component
                    pos= obj.Component(iComp).Position;
                    lengthArray(end+1) = hypot(pos(4) - pos(2),pos(3) - pos(1));
                end
            end

            % Find the index for the longest component connected to source
            if ~isempty(lengthArray)
                [~, idxMax] = max(lengthArray);
                iCompLongest = iCompSrcConnectedArray(idxMax);
            else
                iCompLongest = [];
            end

            % Find block position of longest connected component
            blockPositionLongest = obj.DiscreteElement(iCompLongest,1).BlockPosition;

            % Assign position & orientation of connection port based on
            % direction or orientation of the longest connected component
            if contains(obj.ConnectivityData(iCompLongest).Component,"pipe","IgnoreCase",true)
                % Find direction of longest component
                orientLongest = obj.Component(iCompLongest).Direction;
            elseif contains(obj.ConnectivityData(iCompLongest).Component,"bend","IgnoreCase",true)
                % Find orientation of longest component
                orientLongest = obj.Component(iCompLongest).Orientation;
            end

            if contains(orientLongest, "right")
                blockPositionFluidIn(1) = blockPositionLongest(1) - obj.Canvas.ScaleX*obj.Plate.PartitionWidth;
                blockPositionFluidIn(2) = blockPositionLongest(2) + 0.5*obj.Canvas.PipeBlockSize(2);
            elseif contains(orientLongest, "left")
                blockPositionFluidIn(1) = blockPositionLongest(1) + obj.Canvas.ScaleX*obj.Plate.PartitionWidth;
                blockPositionFluidIn(2) = blockPositionLongest(2) + 0.5*obj.Canvas.PipeBlockSize(2);
            elseif contains(orientLongest, "up")
                blockPositionFluidIn(1) = blockPositionLongest(1) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockPositionFluidIn(2) = blockPositionLongest(4) + obj.Canvas.ScaleY*obj.Plate.PartitionHeight;
            elseif contains(orientLongest, "down")
                blockPositionFluidIn(1) = blockPositionLongest(1) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockPositionFluidIn(2) = blockPositionLongest(2) - obj.Canvas.ScaleY*obj.Plate.PartitionHeight;
            end
            blockOrientFluidIn = orientLongest;

            blockPositionFluidIn(3) = blockPositionFluidIn(1) + connPortWidth;
            blockPositionFluidIn(4) = blockPositionFluidIn(2) + connPortHeight;

        end

        function [blockPositionFluidOut, blockOrientFluidOut] = computeFluidOutPortPosition(obj)
        % Compute position and orientation of fluid outport of flow network subsystem
        arguments (Input)
            obj 
        end

        arguments (Output)
            blockPositionFluidOut (1,4) double
            blockOrientFluidOut (1,1) string
        end

            iCompSinkConnectedArray = [];
            lengthArray = [];
            connPortWidth = 30;
            connPortHeight = 16;

            for iComp = 1:obj.NumComponents
                % Find connected components with sink
                if strcmpi(obj.ConnectivityData(iComp).Connectivity.portBConnectedComponent, "Sink")

                    iCompSinkConnectedArray(end+1) =  iComp;

                    % Find the lengths of connected component
                    pos= obj.Component(iComp).Position;
                    lengthArray(end+1) = hypot(pos(4) - pos(2),pos(3) - pos(1));
                end
            end

            % Find the index for the longest component connected to sink
            if ~isempty(lengthArray)
                [~, idxMax] = max(lengthArray);
                iCompLongest = iCompSinkConnectedArray(idxMax);
            else
                iCompLongest = [];
            end

            % Find block position of longest connected component
            blockPositionLongest = obj.DiscreteElement(iCompLongest,obj.Component(iCompLongest).NumDiscretize).BlockPosition;

            % Assign position & orientation of connection port based on
            % direction or orientation of the longest connected component
            if contains(obj.ConnectivityData(iCompLongest).Component,"pipe","IgnoreCase",true)
                % Find direction of longest component
                orientLongest = obj.Component(iCompLongest).Direction;
            elseif contains(obj.ConnectivityData(iCompLongest).Component,"bend","IgnoreCase",true)
                % Find orientation of longest component
                orientLongest = obj.Component(iCompLongest).Orientation;
            end

            if contains(orientLongest, "right")
                blockPositionFluidOut(1) = blockPositionLongest(3) + obj.Canvas.ScaleX*obj.Plate.PartitionWidth;
                blockPositionFluidOut(2) = blockPositionLongest(2) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockOrientFluidOut = "left";
            elseif contains(orientLongest, "left")
                blockPositionFluidOut(1) = blockPositionLongest(1) - obj.Canvas.ScaleX*obj.Plate.PartitionWidth;
                blockPositionFluidOut(2) = blockPositionLongest(2) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockOrientFluidOut = "right";
            elseif contains(orientLongest, "up")
                blockPositionFluidOut(1) = blockPositionLongest(1) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockPositionFluidOut(2) = blockPositionLongest(2) - obj.Canvas.ScaleY*obj.Plate.PartitionHeight;
                blockOrientFluidOut = "down";
            elseif contains(orientLongest, "down")
                blockPositionFluidOut(1) = blockPositionLongest(1) + 0.5*obj.Canvas.PipeBlockSize(2);
                blockPositionFluidOut(2) = blockPositionLongest(4) + obj.Canvas.ScaleY*obj.Plate.PartitionHeight;
                blockOrientFluidOut = "up";
            end

            blockPositionFluidOut(3) = blockPositionFluidOut(1) + connPortWidth;
            blockPositionFluidOut(4) = blockPositionFluidOut(2) + connPortHeight;

        end

        %% CONNECT FLOW AND THERMAL COMPONENTS TO THERMAL ARRAY FOR BATTERY NODES
        function connectFlowToThermalArray(obj)
        % Connect flow network subsystem and thermal network component with 
        % array connection for battery nodes
            arguments
                obj ComponentConnectivity
            end

            connPortLibPath = "nesl_utility/Connection Port";
            pressureTempSensorLibPath = sprintf("fl_lib/Thermal Liquid/Sensors/Pressure &\nTemperature Sensor\n(TL)");

            % Add Connection ports (fluid_in, fluid_out, H, T) for cooling plate subsystem
            fluidInPortCoolingPlate = strcat(obj.CoolingPlateSystem, "/fluid_in");
            fluidOutPortCoolingPlate = strcat(obj.CoolingPlateSystem, "/fluid_out");
            surf1PortCoolingPlate = strcat(obj.CoolingPlateSystem, "/Surf1");
            TpPortCoolingPlate = strcat(obj.CoolingPlateSystem, "/Tp");

            add_block(connPortLibPath,fluidInPortCoolingPlate,"Position",[20, 108, 50, 122]);
            add_block(connPortLibPath,fluidOutPortCoolingPlate,"Position",[450, 138, 480, 152]);
            add_block(connPortLibPath,surf1PortCoolingPlate,"Position",[20, 188, 50, 202]);
            add_block(connPortLibPath,TpPortCoolingPlate,"Position",[450, 213, 480, 227]);

            % Add pressure & temperature sensor
            pressureTempSensor = strcat(obj.CoolingPlateSystem, sprintf("/Pressure &\nTemperature Sensor\n(TL)"));
            dTPortCoolingPlate = strcat(obj.CoolingPlateSystem, "/dT");
            dPPortCoolingPlate = strcat(obj.CoolingPlateSystem, "/dP");
            add_block(pressureTempSensorLibPath,pressureTempSensor,"Position",[275, -15, 315, 25]);
            set_param(pressureTempSensor,"Orientation","left");
            set_param(pressureTempSensor,"pressure","true","temperature","true");
            set_param(pressureTempSensor,"reference","foundation.enum.MeasurementReference.difference");

            % Add cooling plate subsystem connection ports for sensor signals
            add_block(connPortLibPath,dTPortCoolingPlate,"Position",[335, 50, 365, 64]);
            add_block(connPortLibPath,dPPortCoolingPlate,"Position",[200, 18, 230, 32]);
            set_param(dPPortCoolingPlate,"Orientation","right");

            % Set fluid_in, fluid_out, H, Tp, dT, dP port locations on parent subsystem
            set_param(surf1PortCoolingPlate,"Orientation","Right","Port","1","Side","Left");
            set_param(fluidInPortCoolingPlate,"Orientation","Right","Port","2","Side","Left");

            set_param(fluidOutPortCoolingPlate,"Orientation","Left","Port","3","Side","Right");
            set_param(TpPortCoolingPlate,"Orientation","Left","Port","4","Side","Right");
            set_param(dTPortCoolingPlate,"Orientation","Left","Port","5","Side","Right");
            set_param(dPPortCoolingPlate,"Orientation","Right","Port","6","Side","Right");

            % Move surf1 port to top on parent subsystem
            pHandlesCoolingPlateSystem = get_param(obj.CoolingPlateSystem,"PortHandles");
            surf1PortHandleCoolingPlate = pHandlesCoolingPlateSystem.LConn(1);
            placeSubsystemPort(surf1PortHandleCoolingPlate,"Top");

            % Connect flow and thermal ports
            simscape.addConnection(obj.FlowSystem,"H",obj.CoolingPlateThermalComponent,"Cool","autorouting","smart");
            simscape.addConnection(obj.FlowSystem,"fluid_in",fluidInPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(obj.FlowSystem,"fluid_out",fluidOutPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(obj.CoolingPlateThermalComponent,"Batt",surf1PortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(obj.CoolingPlateThermalComponent,"plotPlateT",TpPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(obj.CoolingPlateSystem,"Surf1",obj.CoolingPlateToBatteryArrayConn,"arrayNode","autorouting","smart");

            % Connect sensor ports to cooling plate subsystem ports
            simscape.addConnection(pressureTempSensor,"A",fluidOutPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(pressureTempSensor,"B",fluidInPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(pressureTempSensor,"T",dTPortCoolingPlate,"port","autorouting","smart");
            simscape.addConnection(pressureTempSensor,"P",dPPortCoolingPlate,"port","autorouting","smart");

        end
        
        function obj = createMaskFlowSystem(obj)
        % Create a mask for the flow network subsystem
            arguments
                obj ComponentConnectivity
            end

            % Create a mask object for flow subsystem
            Simulink.Mask.create(obj.FlowSystem);
            maskObj = Simulink.Mask.get(obj.FlowSystem);

            % Create mask icon image
            obj = obj.createMaskIconCoolingPlate;

            % Add mask icon from created image file
            maskObj.Display = sprintf('image(''%s'')', obj.Mask.IconImageName);
            maskObj.IconOpaque = "opaque-with-ports";

        end

        function obj = createMaskCoolingPlate(obj)
        % Create a mask for the cooling plate subsystem
            arguments
                obj ComponentConnectivity
            end

            % Create a mask object for cooling plate subsystem
            Simulink.Mask.create(obj.CoolingPlateSystem);
            maskObj = Simulink.Mask.get(obj.CoolingPlateSystem);

            % Add a Group Box
            maskObj.addDialogControl('Type', 'group', 'Name', 'MainGroup', ...
                'Prompt', 'Settings');

            % Add Collapsible Panels
            maskObj.addDialogControl("Type", "collapsiblepanel", "Name", "InterfacePanel", "Container", "MainGroup", ...
                "Prompt", "Interface", "Expand", "on", "AlignPrompts", "on");
            % 'Options', 'Collapse');

            maskObj.addDialogControl("Type", "collapsiblepanel", "Name", "MaterialPanel", "Container", "MainGroup", ...
                "Prompt", "Plate Material", "Expand", "on", "AlignPrompts", "on");

            % Add parameters to panels
            maskObj.addParameter("Type", "edit", "Name", "numBattThermalNodes", "Prompt", "Number of battery thermal nodes", ...
                "Value", "1", "Container", "InterfacePanel");

            maskObj.addParameter("Type", "edit", "Name", "dimensionThermalNodes", "Prompt", "Dimension of battery thermal nodes (m)", ...
                "Value", "ones(1, 2)", "Container", "InterfacePanel");

            maskObj.addParameter("Type", "edit", "Name", "locationThermalNodes", "Prompt", "Coordinates of battery thermal nodes (m)", ...
                "Value", "ones(1, 2)", "Container", "InterfacePanel");

            maskObj.addParameter("Type", "edit", "Name", "plateDimX", "Prompt", "Number of partitions in X direction", ...
                "Value", "2", "Container", "InterfacePanel");

            maskObj.addParameter("Type", "edit", "Name", "plateDimY", "Prompt", "Number of partitions in Y direction", ...
                "Value", "5", "Container", "InterfacePanel");

            maskObj.addParameter("Type", "edit", "Name", "thkPlate", "Prompt", "Thickness of cooling plate (m)", ...
                "Value", "2e-3", "Container", "MaterialPanel");

            maskObj.addParameter("Type", "edit", "Name", "thCondPlate", "Prompt", "Thermal conductivity of cooling plate material (W/(K*m))", ...
                "Value", "20", "Container", "MaterialPanel");

            maskObj.addParameter("Type", "edit", "Name", "rhoPlate", "Prompt", "Density of cooling plate material (kg/m^3)", ...
                "Value", "2500", "Container", "MaterialPanel");

            maskObj.addParameter("Type", "edit", "Name", "cpPlate", "Prompt", "Specific heat of cooling plate material (J/(K*kg))", ...
                "Value", "447", "Container", "MaterialPanel");

            maskObj.addParameter("Type", "edit", "Name", "initTempPlate", "Prompt", "Initial temperature of cooling plate and coolant (K)", ...
                "Value", "300", "Container", "MaterialPanel");

            % Disable editing of parameters under 'Interface' panel
            maskObj.getParameter("numBattThermalNodes").Enabled = "off";
            maskObj.getParameter("dimensionThermalNodes").Enabled = "off";
            maskObj.getParameter("locationThermalNodes").Enabled = "off";
            maskObj.getParameter("plateDimX").Enabled = "off";
            maskObj.getParameter("plateDimY").Enabled = "off";

            % Add mask icon from already existing/created image file
            maskObj.Display = sprintf('image(''%s'')', obj.Mask.IconImageName);
            maskObj.IconOpaque = "opaque-with-ports";

        end

        function obj = createMaskIconCoolingPlate(obj)
        % Create mask icon for the cooling plate subsystem
            arguments
                obj ComponentConnectivity
            end

            % Plot cooling plate edges
            plateWidth = obj.Plate.xMaxPlate - obj.Plate.xMinPlate;
            plateHeight = obj.Plate.yMaxPlate - obj.Plate.yMinPlate;

            fig = figure("Visible", "off", "color", "w");
            rectangle("Position",[obj.Plate.xMinPlate obj.Plate.yMinPlate plateWidth plateHeight],"LineWidth",4,"EdgeColor",[0 0 0]);
            hold on

            % Plot cooling pipe components
            pipeIconColor = [255, 191, 0]/255;
            for iComp = 1:numel(obj.Component)
                plot([obj.Component(iComp).Position(1) obj.Component(iComp).Position(3)], ...
                    [obj.Component(iComp).Position(2) obj.Component(iComp).Position(4)],"LineWidth",3,"Color",pipeIconColor);
                hold on
            end
            axis off;

            % Get fullfile path of Images folder
            projectRootFolder = fileparts(fileparts(mfilename('fullpath')));            
            imageFolder = fullfile(projectRootFolder, 'Images');

            % Save figure as a |png| file in Images folder
            obj.Mask.IconImageName = "CoolingPlateMaskIcon.png";
            saveImgPath = fullfile(imageFolder, [obj.Mask.IconImageName]);
            saveas(fig,saveImgPath);
            close(fig);

        end

        function setFlowParametersInModel(obj)
        % Set block parameters in flow network subsystem
            arguments
                obj ComponentConnectivity
            end

            for iComp = 1:obj.NumComponents
                for iDisc = 1:obj.Component(iComp).NumDiscretize

                    if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                        blockHandle = obj.DiscreteElement(iComp,iDisc).BlockHandlesFlow;
                    elseif contains(obj.ConnectivityData(iComp).Component,"bend","IgnoreCase",true)
                        blockHandle = obj.DiscreteElement(iComp,iDisc).BlockHandlesFlow;
                    end

                    set_param(blockHandle,"lengthPipe",string(obj.DiscreteElement(iComp,iDisc).Length));
                    diaPipeValue = value(convert(obj.ConnectivityData(iComp).Parameters.diameter,"m"));
                    set_param(blockHandle,"diaPipe",string(diaPipeValue));
                    set_param(blockHandle,"areaPipe",string(pi*0.25*diaPipeValue^2));
                end
            end

        end

        function setThermalParametersInModel(obj,numBattThermalNodes,dimensionThermalNodes,...
                locationThermalNodes,numPartitionsX,numPartitionsY)
        % Set parameters in Simscape Component for thermal network
        arguments
                obj ComponentConnectivity
                numBattThermalNodes (1,1) {mustBeInteger}
                dimensionThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(dimensionThermalNodes, 'm')}
                locationThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(locationThermalNodes, 'm')}
                numPartitionsX (1,1) {mustBeInteger}
                numPartitionsY (1,1) {mustBeInteger}
            end

            % Verify whether battery thermal nodes lie inside the cooling
            % plate
            ComponentConnectivity.verifyNodesInsidePlate(obj,numBattThermalNodes,locationThermalNodes)

            % Set mask parameters for cooling plate interface
            set_param(obj.CoolingPlateSystem,"numBattThermalNodes",string(numBattThermalNodes));
            set_param(obj.CoolingPlateSystem,"dimensionThermalNodes",mat2str(value(dimensionThermalNodes)));
            set_param(obj.CoolingPlateSystem,"locationThermalNodes",mat2str(value(locationThermalNodes)));
            set_param(obj.CoolingPlateSystem,"plateDimX",string(numPartitionsX));
            set_param(obj.CoolingPlateSystem,"plateDimY",string(numPartitionsY));

            % Set parameters for interface of thermal component of cooling plate
            set_param(obj.CoolingPlateThermalComponent,"numBattThermalNodes","numBattThermalNodes");
            set_param(obj.CoolingPlateThermalComponent,"dimensionThermalNodes","dimensionThermalNodes");
            set_param(obj.CoolingPlateThermalComponent,"locationThermalNodes","locationThermalNodes");
            set_param(obj.CoolingPlateThermalComponent,"plateDimX","plateDimX");
            set_param(obj.CoolingPlateThermalComponent,"plateDimY","plateDimY");
            set_param(obj.CoolingPlateThermalComponent,"numFluidElem",string(length(obj.DiscreteElemPartition)));
            set_param(obj.CoolingPlateThermalComponent,"connfluidToPlateMat",mat2str(obj.DiscreteElemPartition));

            % Set cooling plate material properties
            setMaterialPropertiesInModel(obj)

        end

        function setMaterialPropertiesInModel(obj)
        % Set cooling plate material properties in model
        arguments
                obj ComponentConnectivity
        end

            % Set mask parameters for cooling plate material
            set_param(obj.CoolingPlateSystem,"thkPlate",string(value(obj.MaterialProp.ThicknessPlate)));
            set_param(obj.CoolingPlateSystem,"thCondPlate",string(value(obj.MaterialProp.ThermalConductivityPlate)));
            set_param(obj.CoolingPlateSystem,"rhoPlate",string(value(obj.MaterialProp.DensityPlate)));
            set_param(obj.CoolingPlateSystem,"cpPlate",string(value(obj.MaterialProp.SpecificHeatPlate)));
            set_param(obj.CoolingPlateSystem,"initTempPlate",string(value(obj.MaterialProp.InitialTemperaturePlate)));

            % Set parameters for plate material
            set_param(obj.CoolingPlateThermalComponent,"plateTh","thkPlate");
            set_param(obj.CoolingPlateThermalComponent,"plateTh_unit",string(unit(obj.MaterialProp.ThicknessPlate)));
            set_param(obj.CoolingPlateThermalComponent,"plateThCond","thCondPlate");
            set_param(obj.CoolingPlateThermalComponent,"plateThCond_unit",string(unit(obj.MaterialProp.ThermalConductivityPlate)));
            set_param(obj.CoolingPlateThermalComponent,"plateDen","rhoPlate");
            set_param(obj.CoolingPlateThermalComponent,"plateDen_unit",string(unit(obj.MaterialProp.DensityPlate)));
            set_param(obj.CoolingPlateThermalComponent,"plateCp","cpPlate");
            set_param(obj.CoolingPlateThermalComponent,"plateCp_unit",string(unit(obj.MaterialProp.SpecificHeatPlate)));
            set_param(obj.CoolingPlateThermalComponent,"plateTemp_ini","initTempPlate");
            set_param(obj.CoolingPlateThermalComponent,"plateTemp_ini_unit",string(unit(obj.MaterialProp.InitialTemperaturePlate)));

        end

        function setArrayConnParametersInModel(obj,numBattThermalNodes)
            % Set parameters for thermal array block which connects cooling
            % plate thermal component and battery modules
            arguments
                obj ComponentConnectivity
                numBattThermalNodes (1,1) {mustBeInteger}
            end

            set_param(obj.CoolingPlateToBatteryArrayConn,"Mode","Sized Elements");
            elementSizeArray = repmat("[1,1]", numBattThermalNodes, 1);  % Assuming lumped module
            set_param(obj.CoolingPlateToBatteryArrayConn, "ElementSizes", elementSizeArray);

        end

        function saveCoolingPlateLib(obj)
            % Save cooling plate masked subsystem in a locked library

            projectRootFolder = fileparts(fileparts(mfilename("fullpath")));
            componentsFolder = fullfile(projectRootFolder, "Components");
            libName = strcat(obj.ModelName,"_lib");
            libFilePath = fullfile(componentsFolder, libName);

            % Save & suppress only relevant warnings
            % warnState = warning;
            % c = onCleanup(@() warning(warnState));
            % warning('off','Simulink:Engine:ShadowedModelName');
            % warning('off','Simulink:LoadSave:ShadowedModelName');

            % Close & delete if library exists
            if bdIsLoaded(libName)
                close_system(libName,0);
            end

            existingFile = which(libName);
            if ~isempty(existingFile)
                delete(existingFile);
            end

            % Create & save library
            new_system(libName,"Library");
            save_system(libName,libFilePath);

            % Load library
            load_system(libName);

            % Get source & destination block paths
            srcBlkPath = obj.CoolingPlateSystem;
            srcBlkName = get_param(srcBlkPath, "Name");
            dstBlkPath = strcat(libName,"/",srcBlkName);

            % Unlock library
            set_param(libName, "Lock", "off");
            if ~isempty(find_system(libName, "SearchDepth", 1, "Name", srcBlkName))             
                delete_block(dstBlkPath);
            end
            % Add source block to destination block path
            add_block(srcBlkPath, dstBlkPath);
            % Lock library
            set_param(libName, "Lock", "on");
            % Save library
            save_system(libName);

            % Close cooling plate model
            close_system(obj.ModelName,0);

        end

    end

    methods (Static)

        function materialProp = storeMaterialProp(thicknessPlate,thermalConductivityPlate,...
                densityPlate,specificHeatPlate,initialTemperaturePlate)
        % Store cooling plate material properties in a structure
        arguments (Input)
            thicknessPlate (1,1) simscape.Value {simscape.mustBeCommensurateUnit(thicknessPlate, 'm')}
            thermalConductivityPlate (1,1) simscape.Value {simscape.mustBeCommensurateUnit(thermalConductivityPlate, 'W/(K*m)')}
            densityPlate (1,1) simscape.Value {simscape.mustBeCommensurateUnit(densityPlate, 'kg/m^3')}
            specificHeatPlate (1,1) simscape.Value {simscape.mustBeCommensurateUnit(specificHeatPlate, 'J/(K*kg)')}
            initialTemperaturePlate (1,1) simscape.Value {simscape.mustBeCommensurateUnit(initialTemperaturePlate, 'K')}
        end

        arguments (Output)
            materialProp (1,1) struct
        end

            materialProp.ThicknessPlate = thicknessPlate;
            materialProp.ThermalConductivityPlate = thermalConductivityPlate;
            materialProp.DensityPlate = densityPlate;
            materialProp.SpecificHeatPlate = specificHeatPlate;
            materialProp.InitialTemperaturePlate = initialTemperaturePlate;

        end

        function verifyArraySizeThermalNodes(numBattThermalNodes,dimensionThermalNodes,...
                locationThermalNodes)
        % Verify array size of dimensionThermalNodes and
        % locationThermalNodes parameters for battery modules
            arguments
                numBattThermalNodes (1,1) {mustBeInteger}
                dimensionThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(dimensionThermalNodes, 'm')}
                locationThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(locationThermalNodes, 'm')}
            end

            if size(dimensionThermalNodes,1) ~= numBattThermalNodes
                error("Dimension of dimensionThermalNodes is not consistent with number of battery thermal nodes.")
            end

            if size(locationThermalNodes,1) ~= numBattThermalNodes
                error("Dimension of locationThermalNodes is not consistent with number of battery thermal nodes.")
            end

        end
     
        function createEmptySubsystem(subsystemPath,subsystemPosition)
        % Create an empty subsystem
            arguments
                subsystemPath (1,1) string
                subsystemPosition (1,4) double
            end

            % Add a Subsystem block to the model
            add_block("built-in/Subsystem", subsystemPath,"Position",subsystemPosition);

            % Get all blocks inside the subsystem
            blocks = find_system(subsystemPath, 'SearchDepth', 1, 'Type', 'Block');

            % Loop through the blocks and delete everything except the Subsystem itself
            for i = 2:length(blocks) % Skip the first one, which is the subsystem itself
                delete_block(blocks{i});
            end

            % Delete all lines inside the subsystem
            lines = find_system(subsystemPath, 'FindAll', 'on', 'Type', 'line');
            for i = 1:length(lines)
                delete_line(lines(i));
            end

        end

        function verifyComponentsInsidePlate(obj) %, xMin, xMax, yMin, yMax)
            % Verifies whether all components lie inside plate
            % Returns list of [componentIndex, elementIndex] that lie outside the plate
            arguments
                obj ComponentConnectivity
            end

            outOfPlateComponents = [];

            xMin = obj.Plate.xMinPlate; xMax = obj.Plate.xMaxPlate;
            yMin = obj.Plate.yMinPlate; yMax = obj.Plate.yMaxPlate;
            for iComp = 1:obj.NumComponents
                pos = obj.Component(iComp).Position;  % [x1, y1, x2, y2]
                x1 = pos(1); y1 = pos(2);
                x2 = pos(3); y2 = pos(4);

                if ~(x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax && ...
                        x2 >= xMin && x2 <= xMax && y2 >= yMin && y2 <= yMax)
                    % If either endpoint lies outside the bounds
                    outOfPlateComponents(end+1) = iComp; 
                end
            end

            if isempty(outOfPlateComponents)
                disp('All pipe components lie within the cooling plate region.');
            else
                fprintf('Found %d pipe element(s) outside the cooling plate bounds:\n', numel(outOfPlateComponents));
                tableComponentsOutOfPlate = table(outOfPlateComponents', 'VariableNames', {'ComponentIndex'});
                disp(tableComponentsOutOfPlate)
            end

        end

        function verifyNodesInsidePlate(obj,numBattThermalNodes,locationThermalNodes)
            % Verifies whether a point lies inside a rectangle
            arguments
                obj ComponentConnectivity
                numBattThermalNodes (1,1) {mustBeInteger}
                locationThermalNodes (:,2) simscape.Value {simscape.mustBeCommensurateUnit(locationThermalNodes, 'm')}
            end

            outOfPlateNodes = [];

            for iNode = 1:numBattThermalNodes
                locationNode =  value(locationThermalNodes(iNode,:));
                xNode = locationNode(1); yNode = locationNode(2);
                xPlateCorners = [obj.Plate.xMinPlate,obj.Plate.xMaxPlate,obj.Plate.xMaxPlate,obj.Plate.xMinPlate];
                yPlateCorners = [obj.Plate.yMinPlate,obj.Plate.yMinPlate,obj.Plate.yMaxPlate,obj.Plate.yMaxPlate];
                isInsidePlate = inpolygon(xNode,yNode,xPlateCorners,yPlateCorners);

                if isInsidePlate ~= 1
                    outOfPlateNodes(end+1) = iNode; 
                end

            end

            if isempty(outOfPlateNodes)
                disp('All battery thermal nodes lie within the cooling plate region.');
            else
                fprintf('Found %d battery thermal node(s) outside the cooling plate bounds:\n', numel(outOfPlateNodes));
                tableNodesOutOfPlate = table(outOfPlateNodes', 'VariableNames', {'NodeIndex'});
                disp(tableNodesOutOfPlate)
            end

        end

        function [numGridX, numGridY, scaleX, scaleY] = findCanvasScaling(obj,padding)
        % Determine canvas scaling for flow network subsystem based on positions of discrete pipe elements
        arguments (Input)
            obj ComponentConnectivity
            padding (1,1) double
        end

        arguments (Output)
            numGridX (1,1) {mustBeInteger}
            numGridY (1,1) {mustBeInteger}
            scaleX (1,1) double
            scaleY (1,1) double
        end

            % Determine unique X and Y locations
            xCenters = []; yCenters = [];

            for iComp = 1:obj.NumComponents
                if contains(obj.ConnectivityData(iComp).Component,"pipe","IgnoreCase",true)
                    numDiscElem = obj.Component(iComp).NumDiscretize;
                    for iDisc = 1:numDiscElem
                        pos = obj.DiscreteElement(iComp, iDisc).Position;
                        midX = (pos(1) + pos(3)) / 2;
                        midY = (pos(2) + pos(4)) / 2;
                        xCenters(end+1) = midX;
                        yCenters(end+1) = midY;
                    end
                end
            end

            % Define tolerance for distinguishing y-levels (adjust as needed)
            tolerance = 1e-2; % 10 mm

            % Sort the x-center & y-center values
            sortedX = sort(xCenters(:));
            sortedY = sort(yCenters(:));
            groupedX = sortedX(1);
            groupedY = sortedY(1);

            for i = 2:length(sortedX)
                if abs(sortedX(i) - groupedX(end)) > tolerance
                    groupedX(end+1,1) = sortedX(i); %#ok<*AGROW>
                end
            end
            for i = 2:length(sortedY)
                if abs(sortedY(i) - groupedY(end)) > tolerance
                    groupedY(end+1,1) = sortedY(i); 
                end
            end

            % Effectively unique X-levels and Y-levels
            numGridX = length(groupedX);
            numGridY = length(groupedY);

            % Define spacing & compute canvas size
            blockSpacingX = obj.Canvas.PipeBlockSize(1) + 160; %160
            blockSpacingY = obj.Canvas.PipeBlockSize(2) + 160; %160
            canvasWidth = blockSpacingX * numGridX + 2 * padding;
            canvasHeight = blockSpacingY * numGridY + 2 * padding;

            % Block Spacing factor
            fSpacingX = 1;
            fSpacingY = 1;

            % Recompute scaling
            scaleX = fSpacingX*(canvasWidth - 2 * padding)/(obj.AllComponents.XMax - obj.AllComponents.XMin);
            scaleY = fSpacingY*(canvasHeight - 2 * padding) / (obj.AllComponents.YMax - obj.AllComponents.YMin);

        end

        function blockPosition = findBlockPositionFromCADPosition(componentPos,canvasRefX,canvasRefY,padding,scaleX,scaleY,blockSize)
        % Determine block position from CAD component position
        arguments (Input)
            componentPos (1,4) double
            canvasRefX (1,1) double
            canvasRefY (1,1) double
            padding (1,1) double
            scaleX (1,1) double
            scaleY (1,1) double
            blockSize (1,2) double
        end

        arguments (Output)
            blockPosition (1,4) double
        end

            % Normalize function
            % instead of '+' or addition, use '-(y - yMaxCAD)*scaleY' as top left corner is origin of a Simulink canvas instead of bottom left of a CAD layout
            normalize = @(x, y) [padding + (x - canvasRefX) * scaleX, padding - (y - canvasRefY) * scaleY]; 


            % Midpoint coordinates of pipe from input (CAD/XML or similar)
            midX = (componentPos(1) + componentPos(3)) / 2;
            midY = (componentPos(2) + componentPos(4)) / 2;

            % Convert to Simulink canvas coordinates
            xySim = normalize(midX, midY);
            xSim = xySim(1);
            ySim = xySim(2);

            % Define block rectangle
            x1Block = xSim - blockSize(1)/2;
            x2Block = xSim + blockSize(1)/2;
            y1Block = ySim - blockSize(2)/2;
            y2Block = ySim + blockSize(2)/2;

            blockPosition = [x1Block y1Block x2Block y2Block];

        end

        function orientationPipe = assignOrientationPipe(pipeStartEndPts)
        % Determine and assign pipe orientation as either horizontal or
        % vertical
            arguments (Input)
                pipeStartEndPts (1,4) double
            end

            arguments (Output)
                orientationPipe (1,1) string
            end

            x1 = pipeStartEndPts(1);
            y1 = pipeStartEndPts(2);
            x2 = pipeStartEndPts(3);
            y2 = pipeStartEndPts(4);
            if abs(y2 - y1)/abs(x2 - x1) > 1
                orientationPipe = "vertical";
            else
                orientationPipe = "horizontal";
            end
        end

        function directionPipe = assignDirectionPipe(position,orientation)
        % Determine and assign pipe direction as up, down, left or right
            arguments (Input)
                position (1,4) double
                orientation (1,1) string
            end

            arguments (Output)
                directionPipe (1,1) string
            end

            x1 = position(1); y1 = position(2);
            x2 = position(3); y2 = position(4);

            if strcmpi(orientation,"vertical") && y2 - y1 > 0
                directionPipe = "up";
            elseif strcmpi(orientation,"vertical") && y2 - y1 < 0
                directionPipe = "down";
            elseif strcmpi(orientation,"horizontal") && x2 - x1 > 0
                directionPipe = "right";
            elseif strcmpi(orientation,"horizontal") && x2 - x1 < 0
                directionPipe = "left";
            end

        end

        function bendOrient = assignOrientationBend(bendPos)
        % Determine and assign bend orientation
        arguments (Input)
            bendPos (1,4) double
        end

        arguments (Output)
            bendOrient (1,1) string
        end

            x1Bend = bendPos(1); y1Bend = bendPos(2);
            x2Bend = bendPos(3); y2Bend = bendPos(4);

            if (x2Bend - x1Bend) > 0 && (y2Bend - y1Bend) > 0
                bendOrient = "up-right";
            elseif (x2Bend - x1Bend) > 0 && (y2Bend - y1Bend) < 0
                bendOrient = "down-right";
            elseif (x2Bend - x1Bend) > 0 && (y2Bend - y1Bend) == 0
                bendOrient = "right";
            elseif (x2Bend - x1Bend) < 0 && (y2Bend - y1Bend) > 0
                bendOrient = "up-left";
            elseif (x2Bend - x1Bend) < 0 && (y2Bend - y1Bend) < 0
                bendOrient = "down-left";
            elseif (x2Bend - x1Bend) < 0 && (y2Bend - y1Bend) == 0
                bendOrient = "left";
            elseif (x2Bend - x1Bend) == 0 && (y2Bend - y1Bend) > 0
                bendOrient = "up";
            elseif (x2Bend - x1Bend) == 0 && (y2Bend - y1Bend) < 0
                bendOrient = "down";
            elseif (x2Bend - x1Bend) == 0 && (y2Bend - y1Bend) == 0
                bendOrient = "invalid";
            end

        end

        function [overlapLen, startEndPtsInRect] = findLineRectangleOverlap(rectVerts, lineStart, lineEnd)
        % Determine the overlap between a line segment and a rectangle
        % rectVerts: 4x2 matrix of rectangle vertices [x1 y1; x2 y2; x3 y3; x4 y4]
        % lineStart, lineEnd: 1x2 vectors [x y]
        arguments (Input)
            rectVerts (4,2) double
            lineStart (1,2) double
            lineEnd (1,2) double
        end

        arguments (Output)
            overlapLen (1,1) double
            startEndPtsInRect (:,:) double
        end

            intersections = [];

            % Check if lineStart and/or lineEnd are inside the rectangle
            isStartIn = ComponentConnectivity.isPointInPolygon(lineStart, rectVerts);
            isEndIn   = ComponentConnectivity.isPointInPolygon(lineEnd, rectVerts);

            % Loop through rectangle edges
            for i = 1:4
                p1 = rectVerts(i, :);
                p2 = rectVerts(mod(i,4)+1, :);
                [isect, pt] = ComponentConnectivity.intersectSegments(lineStart, lineEnd, p1, p2);
                if isect
                    intersections(end+1, :) = pt; 
                end
            end

            if isStartIn && isEndIn
                % Case 1: both inside
                overlapLen = norm(lineEnd - lineStart);
                startEndPtsInRect = [lineStart; lineEnd];
            elseif isStartIn && size(intersections,1) < 2
                % Case 2: start inside, end outside
                ptIn = lineStart;
                startEndPtsInRect = [ptIn; intersections(1,:)];
                if ~isempty(intersections)
                    overlapLen = norm(ptIn - intersections(1,:));
                else
                    overlapLen = 0; % touches edge but doesn't cross
                end
            elseif isEndIn && size(intersections,1) < 2
                % Case 3: start outside, end inside
                ptIn = lineEnd;
                startEndPtsInRect = [intersections(1,:); ptIn];
                if ~isempty(intersections)
                    overlapLen = norm(intersections(1,:) - ptIn);
                else
                    overlapLen = 0; % touches edge but doesn't cross
                end
            elseif size(intersections,1) == 2
                % Case 4: intersects at two points
                if norm(intersections(1,:) - lineStart) < norm(intersections(2,:) - lineStart)
                    startPtInRect = intersections(1,:);
                    endPtInRect = intersections(2,:);
                else
                    startPtInRect = intersections(2,:);
                    endPtInRect = intersections(1,:);
                end
                startEndPtsInRect = [startPtInRect; endPtInRect];
                overlapLen = norm(intersections(1,:) - intersections(2,:));
            else
                % Case 5: no overlap
                startEndPtsInRect = [];
                overlapLen = 0;
            end
        end

        function [arcOverlapLen, arcPtsInRect] = findArcRectangleOverlap(rectVerts, arcPts)
        % Find the overlap between a arc segment and a rectangle
            arguments (Input)
                rectVerts (4,2) double
                arcPts (:,2) double
            end

            arguments (Output)
                arcOverlapLen (1,1) double
                arcPtsInRect (:,:) double
            end

            nArcPts = size(arcPts,1);
            arcPtsInRect = [];
            for i = 1:nArcPts-1
                [overlapLen(i), ptsInRect] = ComponentConnectivity.findLineRectangleOverlap(rectVerts,...
                    [arcPts(i,1) arcPts(i,2)],[arcPts(i+1,1) arcPts(i+1,2)]); 

                if overlapLen(i) > 1e-6
                    arcPtsInRect = [arcPtsInRect; ptsInRect]; 
                end

            end
            arcPtsInRect = unique(arcPtsInRect, 'rows', 'stable');
            arcOverlapLen = sum(overlapLen);

        end

        function [intersect, pt] = intersectSegments(A, B, C, D)
        % Determine the intersection point of two line segments, if any
        arguments (Input)
            A (1,2) double
            B (1,2) double
            C (1,2) double
            D (1,2) double
        end

        arguments (Output)
            intersect (1,1) logical
            pt (1,2) double
        end

            pt = [NaN, NaN];
            intersect = false;

            % Line segment intersection using vector math
            AB = B - A;
            CD = D - C;
            AC = C - A;

            denom = det([AB; -CD]);
            if denom == 0
                return;  % Parallel or co-linear
            end

            t = det([AC; -CD]) / denom;
            u = det([AB; AC]) / denom;

            if t >= 0 && t <= 1 && u >= 0 && u <= 1
                pt = A + t * AB;
                intersect = true;
            end
        end

        function inside = isPointInPolygon(pt, poly)
            % Determine points located inside or on edge of a polygon
            arguments (Input)
                pt (1,2) double
                poly (:,2) double
            end

            arguments (Output)
                inside (1,1) logical
            end

            inside = inpolygon(pt(1), pt(2), poly(:,1), poly(:,2));
        end

    end
end