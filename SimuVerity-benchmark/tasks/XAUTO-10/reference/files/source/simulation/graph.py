import matplotlib.pyplot as plt

def display_graphs(time, ax, ay, wheel_velocity, total_slip, yaw_rate, des_rate):
    """
        This function displays the graphs of velocity, slippage, yaw rate, and desired yaw rate
        with respect to time.

        Args:
            time: A list of time data points.
            ax: A list of longitudinal car velocity data points.
            ay: A list of lateral car velocity data points.
            wheel_velocity: A list of wheel velocity data points.
            total_slip: A list of total slippage percentage data points.
            yaw_rate: A list of yaw rate data points.
            des_rate: A list of desired yaw rate data points.

        Returns:
            The function creates two subplots, one displaying the wheel and car velocities and
            slippage, and the other displaying the yaw rate and desired yaw rate.
    """
    fig, (ax1, ax3) = plt.subplots(nrows=2, ncols=1, figsize=(10, 10))

    ax1.plot(time, wheel_velocity, label='Wheel Velocity')
    ax1.plot(time, ax, label='Car Velocity')
    ax1.set_xlabel('Time (s)')
    ax1.set_ylabel('Velocity (M/s)')
    ax1.set_title('Velocity and Slippage')
    ax1.legend(loc='upper left')

    ax2 = ax1.twinx()
    ax2.plot(time, total_slip, label='Slippage', color='Red')
    ax2.set_ylabel('Slippage (%)')
    ax2.legend(loc='upper right')

    ax3.plot(time, yaw_rate, label='Yaw Rate')
    ax3.plot(time, des_rate, label='Desired Rate')
    ax3.set_ylim(-5, 5)
    ax3.set_xlabel('Time (s)')
    ax3.set_ylabel('Yaw Rate (radians/s)')
    ax3.set_title('Yaw Rate and Desired Rate')
    ax3.legend()

    fig.tight_layout()
    plt.show()