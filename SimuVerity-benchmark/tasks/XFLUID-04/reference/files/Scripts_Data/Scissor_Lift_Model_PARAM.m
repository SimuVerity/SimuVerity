% SCISSOR LIFT PARAMETERS
% Copyright 2012-2025 The MathWorks, Inc.

motor_damping = Simulink.Parameter;
motor_damping.CoderInfo.StorageClass = 'SimulinkGlobal';
motor_damping.Value = 0.01*20; %(Nm/(rad/s))

Scissor_Lift_Param.Initial_Angle = 45; % deg


Scissor_Lift_Param.Initial_Angle = 45; % deg
Scissor_Lift_Param.Initial_Cyl_Ext = 50;   % mm
Scissor_Lift_Param.Sensor_Gain = 5/100e-3*0.5; %V/mm

Scissor_Lift_Param.Colors.Yellow = [0.6 0.6 0.0];
Scissor_Lift_Param.Colors.Red = [0.8 0.2 0.0];
Scissor_Lift_Param.Colors.Blue = [0.0 0.6 0.8];
Scissor_Lift_Param.Colors.Dark_Gray = [0.5 0.5 0.5];
Scissor_Lift_Param.Colors.Light_Gray = [0.8 0.8 0.8];

Scissor_Lift_Param.Link.Length = 200; % cm
Scissor_Lift_Param.Link.Width = 15; % cm
Scissor_Lift_Param.Link.Thickness = 4; % cm
Scissor_Lift_Param.Link.Hole_Radius = 5; % cm
Scissor_Lift_Param.Link.Density = 10; 
Scissor_Lift_Param.Link.Color = [0.6 0.6 0.0];
Scissor_Lift_Param.Link.Opacity = 1;

Scissor_Lift_Param.Roller.Init_Pos_Target = Scissor_Lift_Param.Link.Length-2; % cm 
Scissor_Lift_Param.Crossbar.Init_Angle_Target = asin(Scissor_Lift_Param.Roller.Init_Pos_Target/Scissor_Lift_Param.Link.Length)*180/pi-90;

Scissor_Lift_Param.Link_Separation.Outer_Outer = 80; %cm
Scissor_Lift_Param.Link_Separation.Outer_Inner = 10; %cm
Scissor_Lift_Param.Link_Separation.Inner_Inner = Scissor_Lift_Param.Link_Separation.Outer_Outer-Scissor_Lift_Param.Link_Separation.Outer_Inner*2; %cm

Scissor_Lift_Param.Trans_Shaft.Radius = 5; % cm
Scissor_Lift_Param.Trans_Shaft.Density = 1000;
Scissor_Lift_Param.Trans_Shaft.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Trans_Shaft.Opacity = 1;

Scissor_Lift_Param.Conn_Shaft.Length = Scissor_Lift_Param.Link_Separation.Outer_Inner;
Scissor_Lift_Param.Conn_Shaft.Color = Scissor_Lift_Param.Colors.Red;

Scissor_Lift_Param.Link_Pin.Radius = 5; % cm
Scissor_Lift_Param.Link_Pin.Density = 1000;
Scissor_Lift_Param.Link_Pin.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Link_Pin.Opacity = 1;

Scissor_Lift_Param.Roller.Roller_Radius = 8;
Scissor_Lift_Param.Roller.Roller_Length = 6;
Scissor_Lift_Param.Roller.Shaft_Radius = 5;
Scissor_Lift_Param.Roller.Shaft_Length = Scissor_Lift_Param.Link.Thickness*1.1;
Scissor_Lift_Param.Roller.Density = 1000;
Scissor_Lift_Param.Roller.Color = Scissor_Lift_Param.Colors.Dark_Gray;
Scissor_Lift_Param.Roller.Opacity = 1;

Scissor_Lift_Param.Base_Block.Height = Scissor_Lift_Param.Roller.Roller_Radius*2;
Scissor_Lift_Param.Base_Block.Width = Scissor_Lift_Param.Base_Block.Height;
Scissor_Lift_Param.Base_Block.Length = Scissor_Lift_Param.Roller.Roller_Length;
Scissor_Lift_Param.Base_Block.Shaft_Radius = Scissor_Lift_Param.Roller.Shaft_Radius;
Scissor_Lift_Param.Base_Block.Shaft_Length = Scissor_Lift_Param.Link.Thickness*1.1;
Scissor_Lift_Param.Base_Block.Density = 1000;
Scissor_Lift_Param.Base_Block.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Base_Block.Opacity = 1;

Scissor_Lift_Param.Actuator.Bracket.Flange.Width = 70; %cm
Scissor_Lift_Param.Actuator.Bracket.Flange.Height = 20; %cm
Scissor_Lift_Param.Actuator.Bracket.Flange.Thickness = Scissor_Lift_Param.Link.Thickness; %cm
Scissor_Lift_Param.Actuator.Bracket.Flange.Offset = Scissor_Lift_Param.Link.Width/2; %cm
Scissor_Lift_Param.Actuator.Bracket.Flange.Density = 1000; %cm
Scissor_Lift_Param.Actuator.Bracket.Flange.Color = Scissor_Lift_Param.Colors.Red;
Scissor_Lift_Param.Actuator.Bracket.Flange.Opacity = 1;
Scissor_Lift_Param.Actuator.Bracket.Shaft.Radius = Scissor_Lift_Param.Trans_Shaft.Radius;
Scissor_Lift_Param.Actuator.Bracket.Shaft.Density = 1000;
Scissor_Lift_Param.Actuator.Bracket.Shaft.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Actuator.Bracket.Shaft.Opacity = 1;

Scissor_Lift_Param.Actuator.Collar.Radius = Scissor_Lift_Param.Trans_Shaft.Radius*1.3; %cm
Scissor_Lift_Param.Actuator.Collar.Length = 30; %cm
Scissor_Lift_Param.Actuator.Collar.Density = 1000; %cm
Scissor_Lift_Param.Actuator.Collar.Color = [0.5 0.5 0.5]; %cm
Scissor_Lift_Param.Actuator.Collar.Opacity = 1; %cm

Scissor_Lift_Param.Base_Act_Shaft.Radius = Scissor_Lift_Param.Actuator.Collar.Radius*0.9; % cm
Scissor_Lift_Param.Base_Act_Shaft.Length = Scissor_Lift_Param.Link_Separation.Outer_Outer-Scissor_Lift_Param.Base_Block.Length; % cm
Scissor_Lift_Param.Base_Act_Shaft.Density = 1000;
Scissor_Lift_Param.Base_Act_Shaft.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Base_Act_Shaft.Opacity = 1;

Scissor_Lift_Param.Link_Act_Shaft.Radius = Scissor_Lift_Param.Actuator.Collar.Radius*0.9; % cm
Scissor_Lift_Param.Link_Act_Shaft.Length = Scissor_Lift_Param.Link_Separation.Inner_Inner-Scissor_Lift_Param.Link.Thickness; % cm
Scissor_Lift_Param.Link_Act_Shaft.Density = 1000;
Scissor_Lift_Param.Link_Act_Shaft.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Link_Act_Shaft.Opacity = 1;

%%% CHANGE TESTS
Scissor_Lift_Param.Link_Act_Shaft.Offset = Scissor_Lift_Param.Link.Length*0.4;

Scissor_Lift_Param.Actuator.Cylinder.Radius = Scissor_Lift_Param.Trans_Shaft.Radius*1.3; %cm
Scissor_Lift_Param.Actuator.Cylinder.Length = Scissor_Lift_Param.Link.Length*0.675; %cm

Scissor_Lift_Param.Actuator.Piston_Seat.Radius = Scissor_Lift_Param.Trans_Shaft.Radius*1.3; %cm
Scissor_Lift_Param.Actuator.Piston_Seat.Length = 20; %cm
Scissor_Lift_Param.Actuator.Piston.Length = Scissor_Lift_Param.Link.Length*0.675*0.3; %cm
Scissor_Lift_Param.Actuator.Piston.Radius = Scissor_Lift_Param.Actuator.Cylinder.Radius*0.9; %cm
Scissor_Lift_Param.Actuator.Piston.Density = Scissor_Lift_Param.Actuator.Cylinder.Radius*0.9; %cm
Scissor_Lift_Param.Actuator.Piston.Color = Scissor_Lift_Param.Colors.Light_Gray;
Scissor_Lift_Param.Actuator.Piston.Opacity = 1; %cm

Scissor_Lift_Param.Actuator.Damping = 5000; % N/(m/s)

Scissor_Lift_Param.Actuator.Spring.Stiffness = 5e4; %cm
Scissor_Lift_Param.Actuator.Spring.Damping = 9e3; %cm
Scissor_Lift_Param.Actuator.Spring.Equilibrium_Position = Scissor_Lift_Param.Link.Length; %cm

Scissor_Lift_Param.Upper_Platform.Height = 5;
Scissor_Lift_Param.Upper_Platform.Width = Scissor_Lift_Param.Link_Separation.Outer_Outer+20;
Scissor_Lift_Param.Upper_Platform.Length = Scissor_Lift_Param.Link.Length+40;
Scissor_Lift_Param.Upper_Platform.Density = 1000;
Scissor_Lift_Param.Upper_Platform.Color = [0.0 0.6 0.8];
Scissor_Lift_Param.Upper_Platform.Opacity = 1;

Scissor_Lift_Param.Load.Length = Scissor_Lift_Param.Upper_Platform.Width*0.7;
Scissor_Lift_Param.Load.Width = Scissor_Lift_Param.Load.Length;
Scissor_Lift_Param.Load.Height = Scissor_Lift_Param.Load.Length;
Scissor_Lift_Param.Load.Mass = 20;
Scissor_Lift_Param.Load.Density = Scissor_Lift_Param.Load.Mass/Scissor_Lift_Param.Load.Length^3;
Scissor_Lift_Param.Load.Color = Scissor_Lift_Param.Colors.Light_Gray;
Scissor_Lift_Param.Load.Opacity = 1;

%{ 
Scissor_Lift_Param.Cart.Platform.Height = 10;
Scissor_Lift_Param.Cart.Platform.Width = Scissor_Lift_Param.Link_Separation.Outer_Outer+20;
Scissor_Lift_Param.Cart.Platform.Length = Scissor_Lift_Param.Link.Length+40;

Scissor_Lift_Param.Cart.Axle.Radius = 4;
Scissor_Lift_Param.Cart.Axle.Wheel_Distance = 90;
Scissor_Lift_Param.Cart.Axle.Rim.Radius = 20;
Scissor_Lift_Param.Cart.Axle.Rim.Thickness = 15;
Scissor_Lift_Param.Cart.Axle.Rim.Density = 1000;
Scissor_Lift_Param.Cart.Axle.Rim.Color = [0.5 0.5 0.5];
Scissor_Lift_Param.Cart.Axle.Tire.Radius = 30;
Scissor_Lift_Param.Cart.Axle.Tire.Thickness = 25;
Scissor_Lift_Param.Cart.Axle.Tire.Density = 100;
Scissor_Lift_Param.Cart.Axle.Tire.Color = [0 0 0];
Scissor_Lift_Param.Cart.Axle.Wheelbase = Scissor_Lift_Param.Cart.Platform.Length-2*Scissor_Lift_Param.Cart.Axle.Tire.Radius;



%}
    


