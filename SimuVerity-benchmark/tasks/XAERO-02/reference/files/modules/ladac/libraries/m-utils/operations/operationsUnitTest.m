% operationsUnitTest implements test functions operations in m-Utils
%
%   These functions define test cases with well known results.
%   This unit test should be run every time the file has been modified,
%   to prove that results are still as expected.
%   If any changes has been made to the function this test
%   script can be used to find unintended errors.
%
% Example:
%   rt = table(runtests('operationsUnitTest'))
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
function tests = operationsUnitTest
    tests = functiontests(localfunctions);
end


function acosRealTest(testCase)

rng('default')
u = rand(3,4);
u(1,1) = -1.5;
u(1,2) = 1.5;

actSolution = acosReal(u);    
expSolution = real(acos(u));

verifyEqual(testCase, actSolution, expSolution, 'RelTol', 1e-6)

end

function asinRealTest(testCase)

rng('default')
u = rand(3,4);
u(1,1) = -1.5;
u(1,2) = 1.5;

actSolution = asinReal(u);    
expSolution = real(asin(u));

verifyEqual(testCase, actSolution, expSolution, 'RelTol', 1e-6)

end

function acosSqrtTest(testCase)

rng('default')
u = rand(3,4);
u(1,1) = -1;
u(1,2) = -100;

actSolution = sqrtReal(u);    
expSolution = real(sqrt(u));

verifyEqual(testCase, actSolution, expSolution, 'RelTol', 1e-6)

end

function divideFiniteTest(testCase)

rng('default')
A = rand(3,4);
B = rand(3,4);
B(1,1) = 0;
B(1,2) = eps/3;
B(1,3) = -eps/4;

actSolution = divideFinite(A,B);    
B(abs(B)<eps) = eps;
expSolution = A./B;

verifyEqual(testCase, actSolution, expSolution, 'RelTol', 1e-6)

end