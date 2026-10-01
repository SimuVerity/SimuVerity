function f90_xrobo10_log_event(code,instanceId)
%F90_XROBO10_LOG_EVENT Non-invasive event tap for actor operations.
time = NaN;
try
    time = double(get_param(bdroot,"SimulationTime"));
catch
end
row = [time,double(code),double(instanceId)];
name = "F90_XROBO10_EventLog";
try
    log = evalin("base",name);
catch
    log = zeros(0,3);
end
assignin("base",name,[double(log);row]);
end
