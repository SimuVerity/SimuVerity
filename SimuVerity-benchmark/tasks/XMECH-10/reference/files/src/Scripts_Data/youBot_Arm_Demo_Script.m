%% youBot Arm Demo Script
%
% <html>
% <span style="font-family:Arial">
% <span style="font-size:10pt">
% <tr>   <img src="youBot_Arm_System_demoScript_IMAGE.jpg" alt="youBot System Image"><br>
% <br>
% <tr><b><u>Model</u></b><br>
% <tr>1.  <a href="matlab:cd(fileparts(which('youBot_Arm.slx')));open_system('youBot_Arm');">Open youBot Model</a> (see also model <a href="matlab:web('youBot_Arm_Overview.png');">overview</a>, <a href="matlab:youBot_Arm_webopen_file('youBot_Arm.html');">documentation</a>) Logo: <a href="matlab:youBot_logoShowHide('youBot_Arm','show');">show</a>, <a href="matlab:youBot_logoShowHide('youBot_Arm','hide');">hide</a><br>
% <br>
% <tr><b><u>Import from Onshape</u></b><br>
% <tr>2.  View CAD model in Onshape (requires <a href="matlab:youBot_Arm_viewOnshape('getAccount');">Onshape account</a>): <a href="matlab:youBot_Arm_viewOnshape('showArm');">Open in Chrome</a><br>
% <tr>3.  <a href="matlab:youBot_Arm_winopen_file('youBot_CAD_import.mp4');">Video of import from Onshape</a><br>
% <tr>4.  Import From: <a href="matlab:cd(fileparts(which('Get_Onshape_youBot_Model.m')));Get_Onshape_youBot_Model;">Onshape</a>; <a href="matlab:cd(fileparts(which('youBot.xml')));smimport('youBot.xml','ModelName','youBot_importXML','DataFileName','youBot_importXMLDataFile');">Local copy of Simscape Multibody XML file</a><br>
% <tr>5.  URDF <a href="matlab:open_system('youBot_STEP_URDF');">Open Model</a>, <a href="matlab:edit('youBot_STEP.urdf');">View URDF File</a><br>
% <br>
% <tr><b><u>Optimization</u></b><br>
% <tr>6.  Optimization trajectories (friction on): <a href="matlab:youBot_Arm_winopen_file('youBot_optim_res_friction_allTrajectories.mp4');">Video of optimization progress</a><br>
% <tr>7.  Optimization trajectories (friction on): <a href="matlab:web('youBot_optim_res_Friction_allTrajectories.png');">All</a>; <a href="matlab:web('youBot_optim_res_Friction_allTrajectories_clr.png');">Colored by cost</a>; <a href="matlab:web('youBot_optim_res_Friction_initialFinal.png');">Original and final only</a><br>
% <tr>8.  Optimization trajectories (friction off): <a href="matlab:web('youBot_optim_res_noFriction_allTrajectories.png');">All</a>; <a href="matlab:web('youBot_optim_res_noFriction_allTrajectories_clr.png');">Colored by cost</a>; <a href="matlab:web('youBot_optim_res_noFriction_initialFinal.png');">Original and final only</a><br>
% <tr>9.  Optimization trajectories (comparison): <a href="matlab:web('youBot_optim_res_Compare_Trajectories.png');">Original, optimal with and without friction</a><br>
% <br>
% <tr><b><u>Videos and Animations</u></b><br>
% <tr>10.  <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_Control_Motion.mp4');">Full sequence with arm and belts</a><br>
% <tr>11.  <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_SF_MechExp_20sec.mp4');">Full sequence with arm, belts, and Stateflow animation</a><br>
% <tr>12.  <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_Stateflow_Animation.mp4');">Stateflow animation only</a><br>
% <tr>13.  Tracking Camera: <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_Control_Motion_boxRear.mp4');">Behind Box</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_Control_Motion_boxRight.mp4');">Right of Box</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Arm_Control_Motion_Flythrough.mp4');">Fly Through</a><br>
% <tr>14.  Tests: <a href="matlab:youBot_Arm_winopen_file('youBot_Test_Max_Torque_2x.mp4');">Max Torque</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Test_All_35_2x.mp4');">All Joints 35 deg</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Test_Bicep_2x.mp4');">Bicep</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Test_Forearm_2x.mp4');">Forearm</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Test_Wrist_2x.mp4');">Wrist</a><br>
% <br>
% <tr><b><u>Resources</u></b><br>
% <tr>15.  youBot: <a href="matlab:youBot_Arm_winopen_file('youBot_data_sheet.pdf');">Data Sheet</a>, <a href="matlab:youBot_Arm_winopen_file('youBot_Detailed_Specifications_PDF.pdf')">From Wiki</a></a><br>
% <tr>16.  Maxon Data Sheets: <a href="matlab:youBot_Arm_winopen_file('Maxon_EC32_DataSheet_15W.pdf');">EC32 15W</a>; EC45: <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_30W.pdf');">30W</a>,  <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_50W.pdf');">50W</a>,  <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_70W.pdf');">70W</a><br>
% <tr>17.  Maxon Data Sheets: <a href="matlab:youBot_Arm_winopen_file('Maxon_EC32_DataSheet_15W.pdf');">EC32 15W</a>; EC45: <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_30W.pdf');">30W</a>,  <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_50W.pdf');">50W</a>,  <a href="matlab:youBot_Arm_winopen_file('Maxon_EC45_DataSheet_70W.pdf');">70W</a><br>
% <br>
% </style>
% </style>
% </html>
% 
%
% Copyright 2016-2025 The MathWorks, Inc.

