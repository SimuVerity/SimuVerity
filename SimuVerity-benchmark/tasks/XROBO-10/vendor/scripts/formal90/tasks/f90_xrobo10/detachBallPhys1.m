function detachBallPhys1(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        % Ball
        P=W.UserData.HoldedActor2;

        % Change the parent (better API in future)
        P.attachTo([]);

        % Set the Ball properties
        % P.propagate('Friction',true);
        P.Collisions = true;
        P.Physics = true;
        P.Gravity = true;
       

        % falling
        W.UserData.HoldedActor2 = P;
        f90_xrobo10_log_event(5,ShuttleID);
    end

end
