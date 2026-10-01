function F  = obj_sm_four_bar_optim_match_path(mdl,param_v,x_data_des,y_data_des,map_h)
% Objective function to optimize trajectory of four-bar linkage
% Copyright 2017-2025 The MathWorks, Inc.

load_system(mdl);

% Assign values in base workspace
assignin('base','a',param_v(1));
assignin('base','b',param_v(2));

% Use try-catch in case simulation does not complete.
% Some lengths will not permit the driven link to complete a full
% revolution. If the constraints and bounds are not properly defined, the
% try-catch will help ensure the optimization can continue.

try
    % Run simulation
    simOut=sim(mdl);
    
    % Compute cost function
    % Extract data from results
    simlog_xy_pos = simOut.logsout_sm_four_bar_optim.get('xy_pos');
    xy_pos_Data = simlog_xy_pos.Values.Data;
    xy_pos = xy_pos_Data-min(xy_pos_Data);
    
    figure(map_h);
    plot(xy_pos(:,1),xy_pos(:,2));
    plot(x_data_des,y_data_des,'-','LineWidth',1,'Color',[0 0.4 1],'Marker','.','MarkerSize',8,'MarkerFaceColor',[0 0.4 1]);
    legend({'Desired','Initial'});
    
    % Compute cost function
    F = costFcnAreaPerimeter([x_data_des y_data_des],xy_pos);
    
    % Alternate cost function - accurate, but very restricted in use
    %F = costFcnPoints([x_data_des y_data_des],xy_pos);
    
    % For debugging
    %disp(['a: ' num2str(param_v(1)) '  b: ' num2str(param_v(2)) '  F: ' num2str(F)]);
    
catch
    % If simulation fails, set cost function to NaN
    F = NaN;
end

    function cost = costFcnPoints(ref, test)
        % Compute sum of distance separating points of two planar polygons
        %
        % The cost function is the least squares difference of the sum of
        % the distance between the points on the test and desired
        % trajectories. This method is very accurate but very limited in
        % when it can be used.
        % 1. The reference and current trajectory must be defined by the
        %    same number of points
        % 2. The current trajectory will be penalized if its orientation
        %    and origin is not the same as the reference trajectory.
        % Additional calculations (interpolation, find minimum cost after
        % re-orienting test trajectory) could make this cost function
        % applicable in additional cases.
        %
        % To make this cost function useful with the sm_four_bar_optim.slx:
        % 1. The model only produces outputs at specific time intervals
        % 2. The driven link is turned at a constant speed
        % 3. The x-y coordinates are adjusted so that min(x) = 0, min(y) = 0
        
        ref  = ref-min(ref);
        test = test-min(test);
        
        cost = sum(sqrt(sum((ref-test).*(ref-test),2)));
        
    end

    function AreaPerimeterCost = costFcnAreaPerimeter(ref, test)
        % Compute sum of difference between enclosed area and perimeter
        %
        % The cost function is the sum of the difference between the
        % enclosed area and length of the two trajectories.  This method is
        % very flexible as it can be applied to trajectories with different
        % origins, starting points, and number of points in the definition.
        % However, this limited comparison can result in a selected
        % trajectory that does not match the reference trajectory. It also
        % cannot be used for trajectories that cross over themselves.
        % Selecting good initial values for the parameters will help ensure
        % this method leads to the desired trajectory.
        
        area_ref = xyDatatoArea(ref);
        area_test = xyDatatoArea(test);
        
        perimeter_ref = xyDatatoPerimeter(ref);
        perimeter_test = xyDatatoPerimeter(test);
        
        AreaPerimeterCost = (area_ref-area_test)^2+(perimeter_ref-perimeter_test)^2;
        % For debugging
        % disp(num2str([area_ref area_test perimeter_ref perimeter_test AreaPerimeterCost]));
    end

    function area = xyDatatoArea(xy_poly)
        % Compute area of a planar polygon specified by an N x 2 matrix.
        %
        % Area of a planar polygon specified by an N x 2 matrix.  Area is equal to
        % one-half the sum of the determinants:
        %
        %  |   x_i       y_i   |
        %  |                   |
        %  | x_{i+1}   y_{i+1} |
        %
        % as i ranges over [1, N] and i+1 is computed in modular fashion.
        %
        % This method will produce the wrong answer for self-intersecting
        % polygons (one side crosses over another). It will work correctly
        % for triangles, regular and irregular polygons, convex or concave
        % polygons.
        
        area = sum(sum(xy_poly .* ([1 -1] .* circshift(xy_poly, [-1 1])))) / 2;
        
    end

    function perimeter = xyDatatoPerimeter(xy_poly)
        % Compute the perimeter of a planar polygon
        % specified by an N x 2 matrix
        
        seg_vectors = circshift(xy_poly, -1) - xy_poly; % Vectors along each polygon segment
        perimeter = sum(sqrt(sum(seg_vectors .* seg_vectors, 2)));  % Sum of segment lengths
    end

end
