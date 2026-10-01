from python_anesthesia_simulator.alarms import standard_alarm
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

time = np.arange(400)
signal_dataframe = pd.DataFrame({
    'Time': time,
    'BIS': np.ones_like(time)*50,
    'HR': np.ones_like(time)*60,
    'MAP': np.ones_like(time)*80,
})
# because the function is a loop over the signals, testing one signal should be sufficient to ensure proper working of the code
bis_id_dirac_up = 50
bis_id_dirac_down = 70

signal_dataframe.loc[bis_id_dirac_up, 'BIS'] = 80
signal_dataframe.loc[bis_id_dirac_down, 'BIS'] = 10

bis_step_duration = 60
bis_id_step_up = 150
bis_id_step_down = 300

signal_dataframe.loc[bis_id_step_up:bis_id_step_up+bis_step_duration, 'BIS'] = 65
signal_dataframe.loc[bis_id_step_down:bis_id_step_down+bis_step_duration, 'BIS'] = 25

alarm_standard = standard_alarm(signal_dataframe)
alarm_tight = standard_alarm(signal_dataframe, thresholds={'BIS_min': 30, 'BIS_max': 60}, delay={'BIS': 0})
delay = 2
alarm_delay = standard_alarm(signal_dataframe, thresholds={'BIS_min': 30, 'BIS_max': 60}, delay={'BIS': delay})


def test_alarm_dirac():
    """Test that no delayed alarm are trigerred at dirac step time."""
    assert alarm_standard['BIS_high'].iloc[bis_id_dirac_up] == 1
    assert alarm_standard['BIS_low'].iloc[bis_id_dirac_down] == 1

    assert alarm_tight['BIS_high'].iloc[bis_id_dirac_up] == 1
    assert alarm_tight['BIS_low'].iloc[bis_id_dirac_down] == 1


def test_alarm_step():
    """Test that no delayed alarm are trigerred at BIS step time."""

    assert (alarm_tight['BIS_high'].iloc[bis_id_step_up:bis_id_step_up+bis_step_duration] == 1).all()
    assert (alarm_tight['BIS_low'].iloc[bis_id_step_down:bis_id_step_down+bis_step_duration] == 1).all()

    assert (alarm_delay['BIS_high'].iloc[bis_id_step_up+delay:bis_id_step_up+bis_step_duration] == 1).all()
    assert (alarm_delay['BIS_low'].iloc[bis_id_step_down+delay:bis_id_step_down+bis_step_duration] == 1).all()


def test_no_false_alarm():
    """Test that the alarm are not trigerred outside the possible zone."""
    index = alarm_tight.index
    assert (alarm_standard.loc[index != bis_id_dirac_up, 'BIS_high'] == 0).all()
    assert (alarm_standard.loc[index != bis_id_dirac_down, 'BIS_low'] == 0).all()

    alarm_up_id = [bis_id_dirac_up] + list(range(bis_id_step_up, bis_id_step_up+bis_step_duration+1))
    not_alarm_id = [i for i in index if i not in alarm_up_id]
    assert (alarm_tight.loc[not_alarm_id, 'BIS_high'] == 0).all()
    alarm_down_id = [bis_id_dirac_down] + list(range(bis_id_step_down, bis_id_step_down+bis_step_duration+1))
    not_alarm_id = [i for i in index if i not in alarm_down_id]
    assert (alarm_tight.loc[not_alarm_id, 'BIS_low'] == 0).all()

    alarm_up_id = list(range(bis_id_step_up+delay-1, bis_id_step_up+bis_step_duration+1))
    not_alarm_id = [i for i in index if i not in alarm_up_id]
    assert (alarm_delay.loc[not_alarm_id, 'BIS_high'] == 0).all()
    alarm_down_id = list(range(bis_id_step_down+delay-1, bis_id_step_down+bis_step_duration+1))
    not_alarm_id = [i for i in index if i not in alarm_down_id]
    assert (alarm_delay.loc[not_alarm_id, 'BIS_low'] == 0).all()


if __name__ == "__main__":
    titles = ['standard', 'tight', 'tight + delay']
    for id, alarm in enumerate([alarm_standard, alarm_tight, alarm_delay]):
        plt.subplot(3, 1, id+1)
        plt.plot(time, signal_dataframe['BIS'], label='BIS signal')
        plt.plot(time, alarm['BIS_low']*60, '--', label='BIS low')
        plt.plot(time, alarm['BIS_high']*60, '--', label='BIS high')
        plt.grid()
        plt.ylabel(titles[id])
    plt.show()

    test_alarm_dirac()
    test_alarm_step()
    test_no_false_alarm()
    print("All test are successfull")
