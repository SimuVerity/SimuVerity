function destroyCupPhys2(ShuttleID)

    W = sim3d.World.getWorld(bdroot);
    if ~isempty(W)
        Sh=W.Root.findBy('ActorName',['Shuttle' num2str(ShuttleID)],'first');
        H=Sh.findBy('ActorName','Col_box*','first');

        H.Collisions=true;
        f90_xrobo10_log_event(8,ShuttleID);
    end

end
