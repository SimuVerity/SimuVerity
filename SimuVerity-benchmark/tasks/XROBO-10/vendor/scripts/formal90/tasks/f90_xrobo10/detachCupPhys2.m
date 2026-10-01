function detachCupPhys2(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        if isempty(W.UserData.HoldedActorCup2)
            P = W.UserData.HoldedActorCup1;
        else
            P = W.UserData.HoldedActorCup2;
        end
        Sh=W.Root.findBy('ActorName',['Shuttle' num2str(ShuttleID)],'first');
        H=Sh.findBy('ActorName','Col_box*','first');
        
        P.Physics = false;
        P.LinearVelocity = [0 0 0];
        P.AngularVelocity = [0 0 0];
        P.Collisions = false;
        

        % Change the parent (better API in future)
        P.attachTo(H);
        f90_xrobo10_log_event(3,ShuttleID);

       
    end

end
