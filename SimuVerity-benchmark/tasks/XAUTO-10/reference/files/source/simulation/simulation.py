import math
import random
import array as arr
from graph import display_graphs

# Used Terms:
"""
    Yaw Rate: rad/s
    Longitudinal Velocity: Vx, m/s
    Cornering stiffness at rear wheel: Cy_r, N/rad
    Cornering stiffness at front wheel: Cy_f, N/rad
    Inertia Moment: Izz, Kg/m^2
    Mass: m, Kg
    Front wheelbase: lf, m
    Rear wheelbase: lr, m
    Steering Angle, St_a, degrees (Convert from radians)
    Yaw Moment: M_V, Nm
    Yaw Moment around vertical axis: Mz
    Lateral Velocity: Vy, m/s
    Gear Ratio: Gr, -
    Half the track of the car: Tr, m
    Radius of the wheel: Rw, m (0.2286)
"""

# radians/s (wheel speed)
wheelAngularVelocity = 0 

# radians/s^2 (wheel torque basically)
wheelAngularAccel = 28.2744 

# max angular acceleration in radians/s^2
maxAngularAccel = 1 

# Wheel radius in meters
wheelRadius = 0.4

#Slippage in percentage (1.0 as 0%)
slippage = 1.0

# Gear ratio
Gr = 4.1

# Inertia Moment around z axis
Izz = 120

# Half track of rear axle in meters
Tr = 0.6604 

# Radius of wheel
Rw = 0.2286

# lf (float): Distance between the center of gravity and the front axle in meters
lf = 0.885

# lr (float): Distance between the center of gravity and the rear axle in meters
lr = 0.770

# m (float): Mass of the vehicle in kilograms
m = 222.26

# Cy_f (float): Cornering stiffness of the front tires in N/rad
Cy_f = 7085

# Cy_r (float): Cornering stiffness of the rear tires in N/rad
Cy_r = 7302

# v_cg (float): Velocity of the center of gravity in m/s
v_cg = 1

weight = m * 9.81
 
def radians_to_ms(radians):
    """
        Converts an angular velocity from radians per second to linear velocity in meters
        per second.

        Args:
            radians (float): Angular velocity in radians per second.

        Returns:
            ms (float): Linear velocity in meters per second.
    """
    ms = radians * wheelRadius
    return ms

# Function for converting degrees to radians
def degrees_to_radians(degrees):
    """
        Converts an angle from degrees to radians.

        Args:
            degrees (float): Angle in degrees.

        Returns:
            float: Angle in radians.
    """
    return degrees * (math.pi / 180)

def calculate_steer_gradient():
    """
        Calculates the characteristics of the steering gradient of the car, which
        indicates whether the car understeers or oversteers. A positive steering
        gradient indicates understeer, while a negative steering gradient indicates
        oversteer. The steering gradient is influenced by factors such as the
        vehicle's mass distribution, cornering stiffness of the front and rear tires,
        and the distances between the center of gravity and the front and rear axles.

        Args:
            None

        Returns:
            Ku (float): Value that describes the steering gradient of the car. A positive value
                        indicates understeer, while a negative value indicates oversteer.
    """
    Ku = ((lr * m) / (Cy_f * (lf + lr))) - ((lf * m) / (Cy_r * (lf + lr)))

    return Ku

def calculate_desired_yaw_rate(v_cg, delta):
    """
        Calculates the desired yaw rate of a vehicle given the velocity of the center
        of gravity and the steering angle. The desired yaw rate represents the optimal
        angular velocity around the vehicle's vertical axis for a given steering input
        and vehicle speed. By comparing the desired yaw rate to the actual yaw rate, it
        is possible to assess the vehicle's handling performance and stability.

        Args:
            v_cg (float): Velocity of the center of gravity in m/s
            delta (float): Steering angle in radians in rad

        Returns:
            desired_yaw_rate (float): Desired yaw rate of the vehicle in radians per second
    """
    # Calculate Ku using the existing function
    # Ku = calculate_yaw_rate(Cy_f, Cy_r)

    # Calculate the desired yaw rate using the given formula
    desired_yaw_rate = (v_cg / ((lf + lr) + (0.0012965 * math.pow(v_cg, 2)))) * delta

    # Return the calculated desired yaw rate
    return desired_yaw_rate

def calculate_yaw_rate(t, Ku, Vx, St_a, Trr, Trl):
    """
        Calculates the yaw rate of the vehicle given various parameters such as the
        cornering stiffness of the front and rear tires, current velocity, steering angle,
        and torque applied to the rear wheels. The yaw rate is a measure of the vehicle's
        angular velocity around its vertical axis, and it is an important factor in
        understanding the vehicle's handling and stability during turns. Uses a jerk
        calculation that is being divided by time to get acceleration of yaw rate, then
        adding that to yaw rate velocity (Ku).

        Args:
            t, (int): Time in seconds
            Ku, (float): Yaw rate velocity in radians/s
            Vx, (float): Current velocity of car in m/s
            St_a, (float): Current steering angle in radians
            Trr, (float): Current power from rear right wheel in Nm
            Trl, (float): Current power from rear left wheel in Nm

        Returns:
            Ku (float): Yaw rate of the vehicle in radians per second
    """
    # Calculate the yaw rate using the given formula
    Ku += ((((-lf * Cy_f + lr * Cy_r) / (Izz * Vx)) - ((lf**2 * Cy_f + lr**2 * Cy_r) / (Izz * Vx))) * Ku + ((lf * Cy_f) / Izz) * St_a + (1 / (0.05 * Izz)) * calculate_delta_torque(Trr, Trl)) / t
    # Return the calculated yaw rate
    return Ku

def calculate_yaw_moment(Trr, Trl):
    """
        Calculates the yaw moment of the vehicle based on the torque applied to the rear
        left and rear right wheels. The yaw moment is an important factor in determining
        how the vehicle will respond to changes in power distribution between the wheels,
        affecting its handling, stability, and overall performance.

        Args:
            Trr (float): Current torque applied to the rear right wheel in Nm.
            Trl (float): Current torque applied to the rear left wheel in Nm.

        Returns:
            M_V (float): Yaw moment of the vehicle in Nm, which represents the rotational
                        force acting on the vehicle around its vertical axis.
    """
    # Calculate the yaw moment using the given formula
    M_V = (Trr - Trl) * Tr

    # Return the calculated yaw moment
    return M_V

def calculate_lateral_velocity(Vx, St_a):
    """
        Calculates the lateral velocity of the vehicle during turns. The lateral velocity
        represents the sideways motion of the vehicle while cornering. A higher lateral
        velocity indicates a greater force acting on the vehicle, which can affect its
        stability and handling.

        Args:
            Vx (float): Current longitudinal velocity of the vehicle in m/s.
            St_a (float): Steering angle in radians.

        Returns:
            Vy (float): Lateral velocity of the vehicle in m/s, which represents the
                        sideways motion of the vehicle during turns.
    """
    # Calculate the lateral velocity using the given formula
    Vy = ((-(Cy_f + Cy_r)/(m * Vx)) + (((-lf * Cy_f + lr * Cy_r)/(m * Vx)) - Vx)) + (Cy_f / (m * Vx)) * St_a

    # Return the calculated lateral velocity
    return Vy

def calculate_delta_torque(Trr, Trl):
    """
        Calculates the difference in torque between the rear left and rear right wheels.
        This difference in torque is important to understand how the vehicle will respond
        to changes in power distribution between the wheels, which can affect the vehicle's
        handling, stability, and overall performance.

        Args:
            Trr (float): Current torque applied to the rear right wheel in Nm.
            Trl (float): Current torque applied to the rear left wheel in Nm.

        Returns:
            delt_T (float): Difference in torque between the rear left and rear right wheels in Nm.
    """
    # Calculate the delta torque using the given formula
    delt_T = (Rw / (2 * Tr * Gr)) * calculate_yaw_moment(Trr, Trl)

    #return delt_T
    return delt_T

def magic_formula(w, p, b=10, c=1.9, d=1, e=.97):
    """
        Implements the Magic Formula, which computes the longitudinal or lateral force
        between the tire and the road surface based on the longitudinal tire slip or
        the wheel slip angle, respectively. The Magic Formula is widely used in tire
        and vehicle dynamics analysis.

        Reference:
            [1] Pacejka, H. B. Tire and Vehicle Dynamics. Elsevier Science, 2005

        Args:
            w (float): Weight applied on the tire [N].
            p (float): Tire slip ratio or slip angle.
            b (float, optional): Stiffness factor. Default value corresponds to dry tarmac.
            c (float, optional): Shape factor. Default value corresponds to dry tarmac.
            d (float, optional): Peak factor. Default value corresponds to dry tarmac.
            e (float, optional): Curvature factor. Default value corresponds to dry tarmac.

        Returns:
            F (float): Longitudinal or lateral force between the tire and the road surface [N].
                       If 'p' is a slip ratio, F is the longitudinal force; if 'p' is a wheel
                       slip angle, F is the lateral force.
    """
    p = p - 1
    F = w * d * math.sin(c * math.atan(b * p * (1 - e) + e * b * p - math.atan(b * p)))
    return F

def steering_wheel_angle_to_steering_angle(steering_wheel_angle):
    """
    Converts steering wheel angle to actual steering angle. It uses if statements
    to determine if input is negative, else it will result in the wrong calculation.
    
    Args:
        steering_wheel_angle (float): Steering *wheel* angle in degrees.
        
    Returns:
        Steering angle in radians.
    """
    if steering_wheel_angle >= 0:
        x = (8.355 * (10**-5)) * (steering_wheel_angle ** 2) + (0.139 * steering_wheel_angle) - 0.03133
    else:
        x = (8.355 * (10**-5)) * (-steering_wheel_angle ** 2) + (0.139 * steering_wheel_angle) - 0.03133
    y = x * (math.pi/180)
    return y


def simulate(v_cg, w_Velocity, rl_torqueWheel, rr_torqueWheel, steering_a):
    """
        Simulates the vehicle dynamics given the initial conditions and returns the
        time series of longitudinal and lateral velocities, wheel velocity, actual
        and desired yaw rates.

        Args:
            v_cg (float): The initial center of gravity velocity in m/s.
            w_Velocity (float): The initial total rear longitudinal velocity of wheels in m/s.
            rl_torqueWheel (float): The initial rear left wheel torque in Nm.
            rr_torqueWheel (float): The initial rear right wheel torque in Nm.
            steering_a (float): The initial steering angle in radians.

        Returns:
            tuple: A tuple containing five lists:
                   1. Longitudinal velocity (m/s) at each time step
                   2. Lateral velocity (m/s) at each time step
                   3. Wheel velocity (m/s) at each time step
                   4. Actual yaw rate (radians/s) at each time step
                   5. Desired yaw rate (radians/s) at each time step
    """
    a_x = arr.array('f', [v_cg])
    a_y = arr.array('f', [0])
    wheel_velocity = arr.array('f', [w_Velocity])
    curr_yaw_rate = arr.array('f', [0])
    des_yaw_rate = arr.array('f', [calculate_desired_yaw_rate(v_cg, steering_a)])

    for i in range(10000):
        rl_wheelAngularAccel = radians_to_ms((2*rl_torqueWheel) / (9 * wheelRadius))
        rr_wheelAngularAccel = radians_to_ms((2*rr_torqueWheel) / (9 * wheelRadius))
        rl_slippage = (v_cg + rl_wheelAngularAccel) / v_cg
        rr_slippage = (v_cg + rr_wheelAngularAccel) / v_cg
        rl_slippage = max(rl_slippage, 1.0)
        rr_slippage = max(rr_slippage, 1.0)
        F = magic_formula(weight / 2, (rl_slippage + rr_slippage) / 2)
        LongAccel = (F / m) / 100
        v_cg = v_cg + LongAccel
        rl_wheelAngularVelocity = rl_slippage * v_cg
        rr_wheelAngularVelocity = rr_slippage * v_cg
        a_x.append(a_x[i] + LongAccel)
        wheel_velocity.append((rl_wheelAngularVelocity + rr_wheelAngularVelocity) / 2)
        a_y.append(calculate_lateral_velocity(v_cg, steering_a))
        curr_yaw_rate.append(calculate_yaw_rate(i + 1, curr_yaw_rate[i], v_cg, steering_a, rr_torqueWheel, rl_torqueWheel))
        des_yaw_rate.append(calculate_desired_yaw_rate(v_cg, steering_a))

    return a_x, a_y, wheel_velocity, curr_yaw_rate, des_yaw_rate

if __name__ == '__main__':
    
    # Simulate vehicle dynamics with given velocities, torque applied to each wheel, and steering wheel angle (in degrees)
    ax, ay, wheel_velocity, yaw_rate, des_rate = simulate(1, 1, 1, 1, steering_wheel_angle_to_steering_angle(-20))

    # desired_yaw_rate = calculate_desired_yaw_rate(random_velocity, random_steering_angle)

    # Calculate time
    i = 1
    time = arr.array('f', [0])
    total_slip = arr.array('f', [((wheel_velocity[i] / ax[i]) - 1) * 100])
    while i < len(ax):
        time.append(i / 100)
        total_slip.append(((wheel_velocity[i] / ax[i]) - 1) * 100)
        i += 1
    
    # Display results
    display_graphs(time, ax, ay, wheel_velocity, total_slip, yaw_rate, des_rate)
