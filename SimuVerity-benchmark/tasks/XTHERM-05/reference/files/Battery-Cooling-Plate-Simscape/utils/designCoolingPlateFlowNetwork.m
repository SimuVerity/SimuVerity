function coolingPlateFlowConnectivityData = designCoolingPlateFlowNetwork()
% designCoolingPlateFlowNetwork: This function helps you interactively 
% create and configure a flow network design for a battery cooling plate. 
% The function creates a connectivity data structure for a cooling plate 
% flow network. Using this function streamlines the design process and enables 
% rapid evaluation of design alternatives, compared to manually creating 
% the connectivity data structure. You can use this connectivity data 
% structure to generate a Simscape™ model.

% Copyright 2025 - 2026 The MathWorks, Inc.

%% Create a figure for user interface
fig = uifigure('Name', 'Design Cooling Plate Flow Network', ...
    'Position', [100 100 900 500]);

%% Create a panel and dropdown in the figure for cooling plate design
p1 = uipanel(fig,"Position",[20 430 480 60],"Title","Select cooling plate design");

ddDesign = uidropdown(p1,'Items',{'Parallel','Serpentine'},...
    'Value','Parallel','Position',[10 10 100 20],...
    'ValueChangedFcn',@designChanged);

%% Create a panel and buttons in the figure for cooling channel configuration
p2 = uipanel(fig,"Position",[20 190 480 230],"Title","Select cooling channels configuration");

configButtons = gobjects(6,1);   % allocate max possible
numConfigs = 5;                  % default for Parallel

createConfigButtons(ddDesign.Value,p2,numConfigs); % initial set

selectedConfig = 1;
connectivityData = [];
coolingPlateFlowConnectivityData = [];

%% Create a panel and edit fields in the figure for cooling channels geometry parameters
p3 = uipanel(fig,"Position",[20 20 480 160],"Title","Set cooling channels geometry");
ddNTurns = []; % Initialize

uilabel(p3,"Position",[10 110 240 20],"Text","Number of channels");
efNChannels = uieditfield(p3,"numeric","Position",[260 110 150 20],"Value",5,'ValueChangedFcn', @(~,~) callCreateDataStruct);
uilabel(p3,"Position",[10 85 240 20],"Text","Channel diameter (m)");
efDChannel = uieditfield(p3,"numeric","Position",[260 85 150 20],"Value",0.002,'ValueChangedFcn', @(~,~) callCreateDataStruct);
uilabel(p3,"Position",[10 60 240 20],"Text","Channel length (m)");
efLChannel = uieditfield(p3,"numeric","Position",[260 60 150 20],"Value",0.2,'ValueChangedFcn', @(~,~) callCreateDataStruct);
uilabel(p3,"Position",[10 35 240 20],"Text","Spacing between adjacent channels (m)");
efSpChannel = uieditfield(p3,"numeric","Position",[260 35 150 20],"Value",0.05,'ValueChangedFcn', @(~,~) callCreateDataStruct);
uilabel(p3,"Position",[10 10 240 20],"Text","Distributor pipe diameter (m)");
efDDistributor = uieditfield(p3,"numeric","Position",[260 10 150 20],"Value",0.002,'ValueChangedFcn', @(~,~) callCreateDataStruct);


%% Create a panel for visualization of the flow network plot 
p4 = uipanel(fig,'Title','Verify design schematic',...
    'Position',[520 120 340 370]);
% Create UI axes in the figure
ax = uiaxes(p4, 'Position', [10 10 320 320]);

%% Create a button to Generate Connectivity Data

uibutton(fig, "push", "Text", sprintf("Generate\nConnectivity Data"), "FontSize",14, "Position", [620 50 140 50], ...
    'ButtonPushedFcn',@(src,evt) designConfirmed());
uiwait(fig);

%% UI Control Functions

    function designChanged(~,~)
    % designChanged: Callback function that updates the user interface 
    % and underlying data when the selected design changes. It retrieves 
    % the current design from ddDesign.Value, determines the number of 
    % configurations based on the design type (Parallel or Serpentine), 
    % creates configuration buttons in container p2, generates parameter 
    % edit fields in container p3, and calls callCreateDataStruct to 
    % refresh the data structure.

        design = ddDesign.Value;

        switch design
            case 'Parallel'
                numConfigs = 5;
            case 'Serpentine'
                numConfigs = 4;
        end

        createConfigButtons(design,p2,numConfigs);
        selectedConfig = 1;
        createParamEditfields(design,p3);
        callCreateDataStruct();
    end

    function createParamEditfields(~,~)
    % createParamEditfields dynamically generates parameter input fields in 
    % the UI based on the selected design type (Parallel or Serpentine). It
    % creates a new panel with appropriate labels and input controls 
    % (numeric edit fields or dropdowns), and assigns ValueChangedFcn 
    % callbacks to update the connectivity data structure whenever a 
    % parameter value changes.
        design = ddDesign.Value; 

        switch design
            case 'Parallel'
                delete(p3);
                p3 = uipanel(fig,"Position",[20 20 480 160],"Title","Set cooling channels geometry");
                uilabel(p3,"Position",[10 110 240 20],"Text","Number of channels");
                efNChannels = uieditfield(p3,"numeric","Position",[260 110 150 20],"Value",5,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 85 240 20],"Text","Channel diameter (m)");
                efDChannel = uieditfield(p3,"numeric","Position",[260 85 150 20],"Value",0.002,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 60 240 20],"Text","Channel length (m)");
                efLChannel = uieditfield(p3,"numeric","Position",[260 60 150 20],"Value",0.2,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 35 240 20],"Text","Spacing between adjacent channels (m)");
                efSpChannel = uieditfield(p3,"numeric","Position",[260 35 150 20],"Value",0.05,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 10 240 20],"Text","Distributor pipe diameter (m)");
                efDDistributor = uieditfield(p3,"numeric","Position",[260 10 150 20],"Value",0.002,'ValueChangedFcn', @(~,~) callCreateDataStruct);

            case 'Serpentine'
                delete(p3);
                p3 = uipanel(fig,"Position",[20 20 480 160],"Title","Set cooling channels geometry");
                uilabel(p3,"Position",[10 110 240 20],"Text","Number of turns");
                ddNTurns = uidropdown(p3,"Position",[260 110 150 20],"Items",{'2','4','6','8','10'},"Value","4",'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 85 240 20],"Text","Channel diameter (m)");
                efDChannel = uieditfield(p3,"numeric","Position",[260 85 150 20],"Value",0.002,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 60 240 20],"Text","Total channel length (m)");
                efLChannel = uieditfield(p3,"numeric","Position",[260 60 150 20],"Value",1,'ValueChangedFcn', @(~,~) callCreateDataStruct);
                uilabel(p3,"Position",[10 35 240 20],"Text","Spacing between adjacent turns (m)");
                efSpChannel = uieditfield(p3,"numeric","Position",[260 35 150 20],"Value",0.05,'ValueChangedFcn', @(~,~) callCreateDataStruct);

        end
    end


    function createConfigButtons(design,configPanel,nButtons)
    % createConfigButtons generates a set of configuration selection 
    % buttons within the specified panel based on the chosen design and the 
    % number of configurations. It creates a grid layout inside configPanel, 
    % and then adds push buttons labeled with configuration numbers and 
    % associated schematic icons. Each button is assigned a ButtonPushedFcn 
    % callback to handle configuration selection.

        % Delete old buttons
        delete(configButtons)
        configButtons = gobjects(nButtons,1);

        % Create a grid layout for 6 buttons (2 rows x 3 columns)
        g = uigridlayout(configPanel, [2 5]);
        g.RowHeight = {'0.5x','0.5x'};
        g.ColumnWidth = {'0.5x','0.5x','0.5x'}; %,'0.5x','0.5x'};
        g.Padding = [10 10 10 10];

        % Create clickable buttons with schematic icons
        for iConfig = 1:nButtons
            configButtons(iConfig) = uibutton(g, 'push', ...
                'Text', sprintf('Configuration %d', iConfig), ...
                'FontSize',10,'Icon', strcat(design,sprintf('ChannelDesign%d.png', iConfig)), ...
                'IconAlignment', 'top', 'ButtonPushedFcn',@(src,evt) configPressed(iConfig));
        end

    end


    function configPressed(idx)
        selectedConfig = idx;
        design = ddDesign.Value; 

        switch design
            case "Parallel"
                callCreateDataStruct;
            case "Serpentine"
                if mod(selectedConfig,2) == 0
                    ddNTurns = uidropdown(p3,"Position",[220 90 150 20],"Items",{'1','3','5','7','9'},...
                        "Value","3",'ValueChangedFcn', @(~,~) callCreateDataStruct);
                else
                    ddNTurns = uidropdown(p3,"Position",[220 90 150 20],"Items",{'2','4','6','8','10'},...
                        "Value","4",'ValueChangedFcn', @(~,~) callCreateDataStruct);
                end
                callCreateDataStruct;
        end

    end


    function callCreateDataStruct

        connectivityData = [];
        design = ddDesign.Value;

        opts.lChannel  = simscape.Value(efLChannel.Value,"m");
        opts.dChannel = simscape.Value(efDChannel.Value,"m");
        opts.spChannel = simscape.Value(efSpChannel.Value,"m");
        
        switch design
            case 'Parallel'
                opts.nChannels = efNChannels.Value;
                opts.dDistributor = simscape.Value(efDDistributor.Value,"m");
                connectivityData = createConnectivityDataStruct(design, selectedConfig, ax, ...
                    "nChannels",opts.nChannels,"lChannel",opts.lChannel,...
                    "dChannel",opts.dChannel,"dDistributor",opts.dDistributor,"spacingChannel",opts.spChannel);
            case 'Serpentine'
                opts.nTurns = str2double(ddNTurns.Value);                
                connectivityData = createConnectivityDataStruct(design, selectedConfig, ax, ...
                    "nTurns",opts.nTurns,"lChannel",opts.lChannel,...
                    "dChannel",opts.dChannel,"spacingChannel",opts.spChannel);
        end
        
    end

    function designConfirmed

        if isempty(connectivityData)
            uialert(fig, "Please complete the design before generating connectivity data.", ...
                "Incomplete Design");
            return;
        end

        design = ddDesign.Value;
        coolingPlateFlowConnectivityData = connectivityData;
    
        uiresume(fig);
        close(fig);

        fprintf("Generated connectivity data for %s channel design, configuration #%d\n", ...
            design, selectedConfig);
    end


end