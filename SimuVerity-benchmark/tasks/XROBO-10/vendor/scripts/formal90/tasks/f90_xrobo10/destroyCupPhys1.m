function destroyCupPhys1(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
         Sh=W.Root.findBy('ActorName',['Shuttle' num2str(ShuttleID)],'first');
        H=Sh.findBy('ActorName','Col_box*','first');
        H.Collisions=false;

        % Change the parent (better API in future)
        P = W.UserData.HoldedActorCup3;
        P.attachTo([]);

        % P.propagate('Friction',true);
        P.Friction = 0.1;
        P.Collisions = true;
        P.Physics = true;
        P.Gravity = true;
       

     
        
        W.UserData.Destroy=P;
        f90_xrobo10_log_event(7,ShuttleID);
    end

end
