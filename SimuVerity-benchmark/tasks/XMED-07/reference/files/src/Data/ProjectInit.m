clear all
close all
clc
% Remember top level directory
TopLvlDir = pwd;
% Open Simulink Project
proj = simulinkproject([TopLvlDir '\InfusionPump.prj']);
% Setup Code Generation Folder
p = simulinkproject;
projectRoot = p.RootFolder;
pCacheFolder   = fullfile( projectRoot , 'Codegen', 'cache' );
pCodeGenFolder = fullfile( projectRoot , 'Codegen' );
Simulink.fileGenControl( 'set', 'CacheFolder', pCacheFolder, ...
   'CodeGenFolder', pCodeGenFolder );
% Change working folder to the "work" folder:
pWorkFolder = fullfile( projectRoot, 'work' );
if ~exist( pWorkFolder, 'dir')
    mkdir( pWorkFolder )
end
cd( pWorkFolder );
% open('DemoGuideLine')
