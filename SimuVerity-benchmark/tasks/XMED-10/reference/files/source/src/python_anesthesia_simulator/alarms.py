import pandas as pd


def standard_alarm(
        dataframe: pd.DataFrame,
        thresholds: dict = None,
        delay: dict = None
) -> pd.DataFrame:
    """
    This function simulate the generation of alarm by standard clinical monitors.

    Threshold and delay to trigger the alarms are parametrable. Only BIS, HR and MAP are currently implemented by default.
    Alarm on other signal can be implemented using the threshold and delay dictionnary.

    Parameters
    ----------
    dataframe : pd.DataFrame
        Dataframe of the patient signal. Must contains the columns Time, BIS, HR, and MAP for default usage.
    threshold : dict, optional
        Threshold to trigger the alarms. Should include the keys: signal_min, and signal_max, where signal are the given signal from wich the alarm are triggered by default :  threshold = {'BIS_min': 20, 'BIS_max': 70, 'MAP_min': 60, 'MAP_max': 110, 'HR_min': 45, 'HR_max': 120}.
    delay : dict, optional
        Delay (in seconds) after which the alarm is triggered. Should include all the signal used in threshold as keys.

    Returns
    -------
    pd.Dataframe
        Return a dataframe with columns Time, signal_high, signal_low for each signal given in the parameter.
    """
    if thresholds is None:
        thresholds = {
            'BIS_min': 20,
            'BIS_max': 70,
            'MAP_min': 60,
            'MAP_max': 110,
            'HR_min': 45,
            'HR_max': 120,
        }  # need to find a source for those default values
    if delay is None:
        delay = {
            'BIS': 0,
            'MAP': 0,
            'HR': 0,
        }
    if 'Time' not in dataframe.columns:
        raise Exception("Time must be a column of the given dataframe.")

    alarm_df = pd.DataFrame({'Time': dataframe['Time']})
    sampling_time = dataframe['Time'].iloc[1] - dataframe['Time'].iloc[0]

    for signal in delay.keys():
        # test that signal_max and signal_min are part of threshold
        if f'{signal}_max' not in thresholds.keys() or f'{signal}_min' not in thresholds.keys():
            raise Exception(f"{signal}_max and {signal}_min should be part of threshold keys.")
        if signal not in dataframe.columns:
            raise Exception(f"{signal} is not a column of the given dataframe.")

        alarm_df[f'{signal}_high'] = dataframe[signal].rolling(
            max(1, int(delay[signal]/sampling_time))).apply(lambda x: x.min() > thresholds[f'{signal}_max'])
        alarm_df[f'{signal}_low'] = dataframe[signal].rolling(
            max(1, int(delay[signal]/sampling_time))).apply(lambda x: x.max() < thresholds[f'{signal}_min'])

    alarm_df = alarm_df.fillna(0)
    return alarm_df
