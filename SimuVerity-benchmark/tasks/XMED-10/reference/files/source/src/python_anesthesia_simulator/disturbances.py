import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import TransferFunction, lfilter


class Disturbances:
    """
    A class to compte time dependent disturbance signal to mimic exogenous action impacting the signals measured on the patient.

    Parameters
    ----------
    dist_profil : str, optional
        disturbance profile, can be:

        - 'realistic' see [Struys2004]_
        - 'realistic2' see [Ionescu2021]_
        - 'liver_transplantation' 
        - 'simple', see [Dumont2009]_
        - 'step':  a simple step function on BIS signal
        - 'VitalDb' See :ref:`disurbance_identification`
        - None: No disturbance

        The default is None.
    start_step : float, optional
        For step profile, start time of the step disturbance (seconds). The default is 600s.
    end_step : float, optional
        For step profile, end time of the step disturbance (seconds). The default is 1200s.
    start_intub_time : float, optional
        For VitalDb profile, start time of the intubation disturbance (seconds). The default is 180s.
    start_surgery_time : float, optional
        For VitalDb profile, start time of the surgery disturbance (seconds). The default is 40 minutes

    Returns
    -------
    none

    References
    ----------
    .. [Struys2004] M. M. R. F. Struys, T. De Smet, S. Greenwald, A. R. Absalom, S. Bingé, and E. P. Mortier,
            “Performance Evaluation of Two Published Closed-loop Control Systems Using Bispectral Index Monitoring:
            A Simulation Study,” Anesthesiology, vol. 100, no. 3, pp. 640–647, Mar. 2004,
            doi: 10.1097/00000542-200403000-00026.
    .. [Ionescu2021] Ionescu, Clara M., et al. "An open source patient simulator for design and evaluation of computer
            based multiple drug dosing control for anesthetic and hemodynamic variables." IEEE Access 9 (2021): 8680-8694.
            doi: 10.1109/ACCESS.2021.3049880
    .. [Dumont2009] G. A. Dumont, A. Martinez, and J. M. Ansermino,
            “Robust control of depth of anesthesia,”
            International Journal of Adaptive Control and Signal Processing,
            vol. 23, no. 5, pp. 435–454, 2009, doi: 10.1002/acs.1087.

    """

    def __init__(
        self,
        dist_profil: str = None,
        start_step: float = 600,
        end_step: float = 1200,
        start_intub_time: float = 3 * 60,
        start_surgery_time: float = 40*60,
    ) -> list:
        """Init the class by creating the table in which to interpolate later.
        """
        self.dist_profil = dist_profil
        if dist_profil == 'realistic':
            # As proposed in M. M. R. F. Struys, T. De Smet, S. Greenwald, A. R. Absalom, S. Bingé, and E. P. Mortier,
            # “Performance Evaluation of Two Published Closed-loop Control Systems Using Bispectral Index Monitoring:
            #  A Simulation Study,”
            # Anesthesiology, vol. 100, no. 3, pp. 640–647, Mar. 2004, doi: 10.1097/00000542-200403000-00026.

            self.disturb_point = np.array([[0,     0,  0, 0],  # time, BIS signal, MAP, CO signals
                                           [9.9,   0,  0, 0],
                                           [10,   20, 10, 0.6],
                                           [12,   20, 10, 0.6],
                                           [13,    0,  0, 0],
                                           [19.9,  0,  0, 0],
                                           [20.2, 20, 10, 0.5],
                                           [21,   20, 10, 0.5],
                                           [21.5,  0,  0, 0],
                                           [26,  -20, -10, -0.8],
                                           [27,   20, 10, 0.9],
                                           [28,   10,  7, 0.2],
                                           [36,   10,  7, 0.2],
                                           [37,   30, 15, 0.8],
                                           [37.5, 30, 15, 0.8],
                                           [38,   10,  5, 0.2],
                                           [41,   10,  5, 0.2],
                                           [41.5, 30, 10, 0.5],
                                           [42,   30, 10, 0.5],
                                           [43,   10,  5, 0.2],
                                           [47,   10,  5, 0.2],
                                           [47.5, 30, 10, 0.9],
                                           [50,   30,  8, 0.9],
                                           [51,   10,  5, 0.2],
                                           [56,   10,  5, 0.2],
                                           [56.5,  0,  0, 0]])

        elif dist_profil == 'realistic2':
            # As proposed in Ionescu, Clara M., et al. "An open source patient simulator for design and evaluation of computer
            # based multiple drug dosing control for anesthetic and hemodynamic variables." IEEE Access 9 (2021): 8680-8694.
            # doi: 10.1109/ACCESS.2021.3049880

            self.disturb_point = np.array([[0,     0,  0, 0],  # time, BIS signal, MAP, CO signals
                                           [9.9,   0,  0, 0],
                                           [10,   20, 10, 0.5],
                                           [15,   20, 10, 0.5],
                                           [15.1,  0,  0, 0],
                                           [19.9,  0,  0, 0],
                                           [20,   20, 10, 0.5],
                                           [25,   20, 10, 0.5],
                                           [25.1,  0,  0, 0],
                                           [26.9, -20, -10, -0.5],
                                           [27,   20, 10, 0.5],
                                           [32,   20, 10, 0.5],
                                           [32.1,  0,  0, 0],
                                           [41.9,  0,  0, 0],
                                           [42,   20, 10, 0.5],
                                           [44,   20, 10, 0.5],
                                           [44.1,  0,  0, 0],
                                           [50,    0,  0, 0],
                                           [50.1, 20, 10, 0.5],
                                           [55,   20, 10, 0.5],
                                           [55.1,  0,  0, 0],
                                           [75,    0,  0, 0],
                                           [75.1, 20, 10, 0.5],
                                           [95,   20, 10, 0.5],
                                           [95.1,  0,  0, 0],
                                           [100,   0,  0, 0]])

        elif dist_profil == 'liverTransplantation':
            # The events in this major surgery are Intubation, Incision, recipient hepatectomy, donor liver implementation,

            self.disturb_point = np.array([[0,     0,  0, 0],  # time, BIS signal, MAP, CO signals
                                           [9.9,   0,  0, 0],    [10,   20, 10, 0.5],    [
                13,   20, 10, 0.5],    [13.1,  0,  0, 0],
                [16,    0,  0, 0],    [16.1, 15,  8, 0.4],    [
                21,   15,  8, 0.4],    [21.1, 20, 10, 0.5],
                [27,   20, 10, 0.5],  [27.1,  0,  0,   0],    [
                29,    0,  0,   0],    [29.1,  5,  2, 0.1],
                [37,    5,  2, 0.1],  [37.1,  0,  0,   0],    [
                39,    0,  0,   0],    [39.1,  5,  2, 0.1],
                [46,    5,  2, 0.1],  [46.1,  0,  0,   0],    [
                51,    0,  0,   0],    [51.1, 10,  5, 0.2],
                [56,   10,  5, 0.2],  [56.1,  0,  0,   0],    [
                65,    0,  0,   0],    [65.1, 10,  5, 0.2],
                [69,   10,  5, 0.2],  [69.1,  0,  0,   0],    [
                78,    0,  0,   0],    [78.1, 10,  5, 0.2],
                [82,   10,  5, 0.2],  [82.1,  0,  0,   0],    [
                88,    0,  0,   0],    [90,    5,  2, 0.1],
                [114,   5,  2, 0.1],  [114.1, 0,  0,   0],    [
                116,   0,  0,   0],    [121.5, 0,  0,   0],
                [123.5, 5,  2, 0.1],  [125.5, 0,  0,   0],    [
                130.5, 0,  0,   0],    [132.5, 5,  2, 0.1],
                [134.5, 0,  0, 0],    [141,   0,  0,   0],    [
                141.1, 10,  5, 0.2],    [145,  10,  5, 0.2],
                [145.1, 0,  0, 0],    [150,   0,  0,   0],    [
                151,  10,  5, 0.2],    [155,  10,  5, 0.2],
                [156,   5,  2, 0.1],  [157,  10,  5, 0.2],    [
                161,  10,  5, 0.2],    [162,   0,  0,   0],
                [165,   0,  0, 0],    [166,   5,  2, 0.1],    [
                169,   5,  2, 0.1],    [169.1, 10,  5, 0.2],
                [171,  10,  5, 0.2],  [172,   0,  0,   0],    [
                173,   0,  0,   0],    [173.5, 10,  5, 0.2],
                [174,   0,  0, 0],    [181,   0,  0,   0],    [
                181.1, 15,  8, 0.4],    [183.5, 15,  8, 0.4],
                [183.6, 0,  0, 0],    [186,   0,  0,   0],    [
                186.1, 10,  5, 0.2],    [189,  10,  5, 0.2],
                [189.1, 0,  0, 0],    [190,   0,  0,   0],    [
                190.1, 5,  2, 0.1],    [193,  5,   2, 0.1],
                [193.1, 0,  0, 0],    [196,   0,  0,   0],    [
                198,   8,  4, 0.1],    [204,  8,   4, 0.1],
                [206,   0,  0, 0],    [208,   0,  0,   0],    [
                210,  10,  5, 0.2],    [222, 10,   5, 0.2],
                [224,   0,  0, 0],    [226,   5,  2, 0.1],    [
                227,  12,  6,  0.3],   [232, 12,   6, 0.3],
                [234,   0,  0, 0],    [237,   0,  0,   0],    [
                238,   8,  4, 0.1],    [251,  8,   4, 0.1],
                [252,   0,  0, 0],    [260,   0,  0,   0],    [
                263,  15,  8, 0.4],    [270, 15,   8, 0.4],
                [273,   5,  2, 0.1],  [338,   5,  2, 0.1],    [341,  0,  0,    0],    [350,  0,   0,   0]])

        elif dist_profil == 'simple':
            # As in G. A. Dumont, A. Martinez, and J. M. Ansermino,
            # “Robust control of depth of anesthesia,”
            # International Journal of Adaptive Control and Signal Processing,
            # vol. 23, no. 5, pp. 435–454, 2009, doi: 10.1002/acs.1087.

            self.disturb_point = np.array([[0,     0,  0, 0],  # time, BIS signal, MAP, CO signals
                                           [19.9,  0,  0, 0],
                                           [20,   20,  5, 0.3],
                                           [23,   20, 10, 0.6],
                                           [24,   15, 10, 0.6],
                                           [26, 12.5,  6, 0.4],
                                           [30, 10.5,  4, 0.3],
                                           [37,   10,  4, 0.3],
                                           [40,    4,  2, 0.1],
                                           [45,  0.5, 0.1, 0.01],
                                           [50,    0,  0,   0]])
        elif dist_profil == 'step':
            self.disturb_point = np.array([[0,     0,  0,   0],  # time, BIS signal, MAP, CO signals
                                           [start_step / 60 - 0.01,   0,  0,   0],
                                           [start_step / 60,    10,  5, 0.3],
                                           [end_step / 60 - 0.01,   10,  5, 0.3],
                                           [end_step / 60,  0,  0,   0],
                                           [30,    0,  0,   0]])
        elif dist_profil == 'VitalDB':
            self.start_intub_time = start_intub_time
            self.start_surgery_time = start_surgery_time
            self.polinom_bis = [
                -8.60412601e-11,
                1.53817088e-07,
                -9.35659716e-05,
                1.14438483e-02,
                8.07370704e+00,
            ]
            self.dist_intub_tpr_tau = 3
            self.dist_intub_sv_tau = 2.7
            self.dist_intub_hr_tau = 40
            self.smooth_factor = 50
            self.dist_surg_tpr_tau = 5 * 60
            self.dist_surg_sv_tau = 3 * 60
            self.dist_surg_hr_tau = 8 * 60
            self.dist_intub_tpr_k = 8.8e-6
            self.dist_intub_sv_k = 0.176
            self.dist_intub_hr_k = 11.94

            self.dist_surg_tpr_k = 8.8e-4
            self.dist_surg_sv_k = 13.65
            self.dist_surg_hr_k = 9.92

            self.disturbance_dynamic()
        elif dist_profil is None:
            pass
        else:
            raise ValueError(
                'dist_profil should be: realistic, realistic2, liverTransplantation, simple, step, VitalDB or None')

    def disturbance_dynamic(self):
        """Compute the disturbance from the VitalDB profile.
        """
        # stimuli input
        length_computation = 10_000
        self.time = np.arange(0, length_computation)
        self.intub_input = np.zeros(length_computation)
        # step disturbance after 3 minutes
        self.intub_input[self.start_intub_time:(self.start_intub_time + 2 * 60)] = 1
        self.surg_input = np.zeros(length_computation)
        self.surg_input[self.start_surgery_time:] = 1  # step disturbance after 40 minutes
        smooth_filter = TransferFunction(
            [1],
            [self.smooth_factor, 1]
        ).to_discrete(1, method='bilinear')
        tf_dist_tpr = TransferFunction(
            [self.dist_intub_tpr_k],
            [self.dist_intub_tpr_tau, 1, 0]
        ).to_discrete(1, method='bilinear')
        tf_dist_sv = TransferFunction(
            [self.dist_intub_sv_k],
            [self.dist_intub_sv_tau, 1, 0]
        ).to_discrete(1, method='bilinear')
        tf_dist_hr = TransferFunction(
            [self.dist_intub_hr_k],
            [self.dist_intub_hr_tau, 1]
        ).to_discrete(1, method='bilinear')

        input_smooth = lfilter(smooth_filter.num, smooth_filter.den, self.intub_input)
        self.dist_tpr = lfilter(tf_dist_tpr.num, tf_dist_tpr.den, input_smooth)
        self.dist_sv = lfilter(tf_dist_sv.num, tf_dist_sv.den, input_smooth)
        self.dist_hr = lfilter(tf_dist_hr.num, tf_dist_hr.den, input_smooth)

        tf_dist_tpr = TransferFunction(
            [self.dist_surg_tpr_k],
            [self.dist_surg_tpr_tau**2, 2 * self.dist_surg_tpr_tau, 1]
        ).to_discrete(1, method='bilinear')
        tf_dist_sv = TransferFunction(
            [self.dist_surg_sv_k],
            [self.dist_surg_sv_tau**2, 2 * self.dist_surg_sv_tau, 1]
        ).to_discrete(1, method='bilinear')
        tf_dist_hr = TransferFunction(
            [self.dist_surg_hr_k],
            [self.dist_surg_hr_tau**2, 2 * self.dist_surg_hr_tau, 1]
        ).to_discrete(1, method='bilinear')

        self.dist_tpr += lfilter(tf_dist_tpr.num, tf_dist_tpr.den, self.surg_input)
        self.dist_sv += lfilter(tf_dist_sv.num, tf_dist_sv.den, self.surg_input)
        self.dist_hr += lfilter(tf_dist_hr.num, tf_dist_hr.den, self.surg_input)

    def compute_dist(self, time: float):
        """Interpolate the disturbance profile for the given time.

        Parameters
        ----------
        time : float or np.ndarray
            Time in seconds, can also be a vector.

        Returns
        -------
        list
            dist_bis, dist_map, dist_co, dist_tpr, dist_sv, dist_hr:
            respectively the additive disturbance to add to the BIS, MAP, CO, TPR, SV, and HR signals.
        """
        if self.dist_profil is not None and self.dist_profil != 'VitalDB':
            dist_bis = np.interp(time / 60, self.disturb_point[:, 0], self.disturb_point[:, 1])
            dist_map = np.interp(time / 60, self.disturb_point[:, 0], self.disturb_point[:, 2])
            dist_co = np.interp(time / 60, self.disturb_point[:, 0], self.disturb_point[:, 3])
            if hasattr(time, '__len__'):
                dist_tpr = [0]*len(time)
                dist_sv = [0]*len(time)
                dist_hr = [0]*len(time)
            else:
                dist_tpr = 0
                dist_sv = 0
                dist_hr = 0
        elif self.dist_profil == 'VitalDB':
            dist_bis = np.polyval(self.polinom_bis, time - self.start_intub_time - 4 * 60)
            dist_bis = np.clip(dist_bis, 0, 100)
            if hasattr(time, '__len__'):
                dist_map = [0]*len(time)
                dist_co = [0]*len(time)
            else:
                dist_map = 0
                dist_co = 0
            dist_tpr = np.interp(time, self.time, self.dist_tpr)
            dist_sv = np.interp(time, self.time, self.dist_sv)
            dist_hr = np.interp(time, self.time, self.dist_hr)

        else:
            if hasattr(time, '__len__'):
                return [[0]*len(time)]*6
            else:
                return [0]*6

        return [dist_bis, dist_map, dist_co, dist_tpr, dist_sv, dist_hr]

    def plot_dist(self):
        """Plot the selected profile.
        """
        Time = np.arange(0, 60*60)
        if self.dist_profil is not None and self.dist_profil != 'VitalDB':
            dist_bis = np.interp(Time / 60, self.disturb_point[:, 0], self.disturb_point[:, 1])
            dist_map = np.interp(Time / 60, self.disturb_point[:, 0], self.disturb_point[:, 2])
            dist_co = np.interp(Time / 60, self.disturb_point[:, 0], self.disturb_point[:, 3])
            dist_tpr = Time*0
            dist_sv = Time*0
            dist_hr = Time*0

        elif self.dist_profil == 'VitalDB':
            dist_bis = np.polyval(self.polinom_bis, Time - self.start_intub_time - 4 * 60)
            dist_bis = np.clip(dist_bis, 0, 100)
            dist_map = Time*0
            dist_co = Time*0
            dist_tpr = np.interp(Time, self.time, self.dist_tpr)
            dist_sv = np.interp(Time, self.time, self.dist_sv)
            dist_hr = np.interp(Time, self.time, self.dist_hr)
        else:
            print("profile is None")
            return
        title = ['BIS', 'MAP', 'CO', 'TPR', 'SV', 'HR']
        for i, dist in enumerate([dist_bis, dist_map, dist_co, dist_tpr, dist_sv, dist_hr]):
            plt.subplot(6, 1, i+1)
            plt.plot(Time/60, dist)
            plt.grid()
            plt.ylabel(title[i])
            if i == 5:
                plt.xlabel('Time (minute)')
        plt.show()
