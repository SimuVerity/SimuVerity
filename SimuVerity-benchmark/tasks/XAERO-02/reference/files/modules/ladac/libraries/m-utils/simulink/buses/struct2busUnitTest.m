% struct2busUnitTest implements struct2bus test functions in m-Utils
%
%   These functions define test cases with well known results.
%   This unit test should be run every time the file has been modified,
%   to prove that results are still as expected.
%   If any changes has been made to the function this test
%   script can be used to find unintended errors.
%
% Example:
%   rt = table(runtests('struct2busUnitTest'))
%
% Literature: 
%   [1] https://blogs.mathworks.com/loren/2013/10/15/function-is-as-functiontests/
%
%   [2] https://de.mathworks.com/help/matlab/matlab_prog/write-function-based-unit-tests-.html
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% Call all subfunction tests in this file
function tests = struct2busUnitTest
    tests = functiontests(localfunctions);
end


function simulinkBusTest(testCase)

evalin('base','clearAllBuses')

% define struct test_struct with several duplicate fieldnames and run
% Simulink file with this struct as bus
sub_struct.a = ones(3,1);
sub_struct.b = 1;
sub_struct2.a = 1;
sub_struct2.b = ones(3,1);
sub_struct3.a = 1;
sub_struct3.b = 1;

test_struct.a = ones(3,1);
test_struct.b = 1;
test_struct.c = sub_struct;
test_struct.f.c = sub_struct;
test_struct.d.c = 2;
test_struct.e.c = sub_struct2;
test_struct.g.c = sub_struct3;

assignin('base','test_struct',test_struct);

struct2bus(test_struct)

sim('struct2bus_sim_test');

end
