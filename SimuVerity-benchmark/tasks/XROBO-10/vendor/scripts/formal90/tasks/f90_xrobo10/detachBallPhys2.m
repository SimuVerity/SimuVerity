function detachBallPhys2(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        % Ball
        P=W.UserData.HoldedActor2;

        % Set the Ball properties
        P.Physics = false;
        P.LinearVelocity = [0 0 0];
        P.AngularVelocity = [0 0 0];
        P.Collisions = false;

        % Change the parent (better API in future)
        P.attachTo(W.UserData.HoldedActorCup1);
       

        % Set the Ball properties
        P.Scale=[1000 1000 1000];
        P.Translation(3)=37;

        

        W.UserData.HoldedActor2 = [];
        W.UserData.HoldedActorCup3 = W.UserData.HoldedActorCup1;
        W.UserData.HoldedActorCup1 = W.UserData.HoldedActorCup2;
        W.UserData.HoldedActorCup2 = [];
        f90_xrobo10_log_event(6,ShuttleID);
    end

end
