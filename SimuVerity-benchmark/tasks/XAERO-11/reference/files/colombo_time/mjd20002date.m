function date = mjd20002date(mjd2000)


% ------------------------- - SpaceART Toolbox - --------------------------

% Compute the year month and day
jd   = mjd20002jd(mjd2000);
date = jd2date(jd);


return