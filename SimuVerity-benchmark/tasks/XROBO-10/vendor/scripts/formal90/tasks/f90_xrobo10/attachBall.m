function attachBall(ID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        % Find the Part object
        P = W.Root.findBy('ActorName',['Ball' num2str(ID)],'first');

        % Change the parent (better API in future)
         P.attachTo(W.UserData.EndEffector2);
        

        % Turn of the physics and stop all movement
        P.Physics = false;
        P.LinearVelocity = [0 0 0];
        P.AngularVelocity = [0 0 0];
        

        % Set the relative location to the EndEffector and change the color
        P.Translation = [0 -0.165 0];

       

        % Store the Part in World's UserData structure to make it easily
        % accesible in the detachPart function
        W.UserData.HoldedActor2 = P;
        f90_xrobo10_log_event(4,ID);
    end

end
