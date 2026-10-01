function attachCup(ID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        % Pick a Cup object from the list of Cups
        P1 = W.UserData.PlasticCups{W.UserData.PlasticCupsSerialNumber};
        W.UserData.PlasticCupsSerialNumber=W.UserData.PlasticCupsSerialNumber-1;
        P=P1.Parent.Parent.Parent;
        
        % Change the parent (better API in future)
        P.attachTo(W.UserData.EndEffector);
       

        % Turn of the physics and stop all movement
        P.Physics = false;
        P.LinearVelocity = [0 0 0];
        P.AngularVelocity = [0 0 0];
      

        % Set the relative location to the EndEffector and change the color
        P.Translation = [0.15 0 0];
        P.Rotation = [0 pi/2 0];


        % Store the Part in World's UserData structure to make it easily
        % accesible in the detachPart function
        W.UserData.HoldedActor = P;
        if isempty(W.UserData.HoldedActorCup1)
            W.UserData.HoldedActorCup1 = P1;
        else
            W.UserData.HoldedActorCup2 = P1;
        end
        f90_xrobo10_log_event(1,ID);
    end

end
