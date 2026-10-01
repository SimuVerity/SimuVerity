function [number] = str_to_number(str)
% STR_TO_NUMBER Convert a number given as a word to its numeric value.
%   [number] = str_to_number(str) takes a string input such as 'two',
%   'three', or 'four' and returns the corresponding numeric value 2, 3, or 4.
%
%   Example:
%       num = str_to_number('two'); % returns 2

    % Convert input to lowercase to ensure case-insensitive matching.
    str = lower(str);
    
    % Use a switch-case to map string values to numbers.
    switch str
        case 'zero'
            number = 0;
        case 'one'
            number = 1;
        case 'two'
            number = 2;
        case 'three'
            number = 3;
        case 'four'
            number = 4;
        case 'five'
            number = 5;
        case 'six'
            number = 6;
        case 'seven'
            number = 7;
        case 'eight'
            number = 8;
        case 'nine'
            number = 9;
        case 'ten'
            number = 10;
        case 'eleven'
            number = 11;
        case 'twelve'
            number = 12;
        otherwise
            error('Input string "%s" is not a supported number.', str);
    end
end
