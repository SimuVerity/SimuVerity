function actorInitialization(Actor, World)
% Reserved keywords:
% - Actor : handle to this actor object
% - World : handle to the world object

actorInfo = getActorConfig(Actor.Name);

Actor.createShape('sphere', [2 2 2]*actorInfo.dim(1)); % twice the radius in each dimension

% Initialize values (optional)
Actor.Scale = 1;
% Actor.Gravity = false;
% Actor.Physics = true;
% Actor.Friction = 0;
% Actor.Restitution = 0.0;
Actor.Collisions = false;
Actor.Color = actorInfo.color;
Actor.Shininess = 0;
Actor.Mobility = sim3d.utils.MobilityTypes.Movable;
Actor.Shadows = false;
Actor.Mass = 0;
% Actor.HitEventEnabled = true;
Actor.OverlapEventEnabled = true;

end