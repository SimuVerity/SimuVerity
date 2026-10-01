function youBot_Arm_viewOnshape(location)
% Copyright 2016-2025 The MathWorks, Inc.

youBot_url = 'https://cad.onshape.com/documents/58888ce7a4f89a0fbe428251/w/83f95055aff518f4d909b00b/e/0a8992b268b7a97a9bc90027';
getAccount_url = 'https://www.onshape.com/cad-pricing?utm_campaign=Mathworks&utm_source=Referrals';

if(strcmp(location,'getAccount'))
    openUrl = getAccount_url;
else
    openUrl = youBot_url;
end

if(ispc)
    eval(['!start chrome "' openUrl '"']);
elseif(ismac)
    eval(['!open -a "Google Chrome" ''' openUrl '''']);
end
