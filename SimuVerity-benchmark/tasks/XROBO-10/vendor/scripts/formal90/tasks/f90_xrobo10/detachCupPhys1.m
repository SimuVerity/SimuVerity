function detachCupPhys1(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W) && ~isempty(W.UserData.HoldedActor)
        if isempty(W.UserData.HoldedActorCup2)
            P = W.UserData.HoldedActorCup1;
        else
            P = W.UserData.HoldedActorCup2;
        end

        % Change the parent (better API in future)
        P.attachTo([]);
       
        % Set the Cup properties
        W.UserData.HoldedActor = P;
         P.Collisions = true;
        P.Physics = true;
        P.Gravity = true;
        f90_xrobo10_log_event(2,ShuttleID);

       
    end

end
