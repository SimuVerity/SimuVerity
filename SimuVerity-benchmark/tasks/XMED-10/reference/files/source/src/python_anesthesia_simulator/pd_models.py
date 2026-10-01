from typing import Optional

import numpy as np
from scipy.integrate import solve_ivp
from scipy.stats import truncnorm
import casadi as cas
from matplotlib import pyplot as plt
from matplotlib import cm


def fsig(x, c50, gam): return x**gam / (c50**gam + x**gam)  # quick definition of sigmoidal function


class BIS_model:
    r"""Model to link Propofol effect site concentration to BIS.

    The equation is:

    .. math:: BIS = E0 - Emax * \frac{U^\gamma}{1+U^\gamma}

    If only the effect of propofol is considered the equation represents a sigmoid function, where:

    .. math:: U = \frac{C_{p,es}}{C_{p,50}}

    If the interaction with remifentanil is considered the equation represents a Surface Response model, where:

    .. math:: U = \frac{U_p + U_r}{1 - \beta \theta + \beta \theta^2}

    for Minto-type surface model and:

    .. math:: U = U_p + U_r + \beta U_p U_r

    for Greco-type surface model, with: 

    .. math:: U_p = \frac{C_{p,es}}{C_{p,50}}
    .. math:: U_r = \frac{C_{r,es}}{C_{r,50}}
    .. math:: \theta = \frac{U_p}{U_r+U_p}


    Parameters
    ----------
    hill_model : str, optional
        'Vanluchene'[Vanluchene2004]_, do not consider the synergistic effect of remifentanil.
        'Eleveld'[Eleveld2018]_, do not consider the synergistic effect of remifentanil.
        'Bouillon'[Bouillon2004]_, considers the synergistic effect of remifentanil (Minto-type surface model).
        'Fuentes'[Fuentes2018]_, considers the synergistic effect of remifentanil (Greco-type surface model).
        'Yumuk'[Yumuk2024]_, considers the synergistic effect of remifentanil (Greco-type).
        Ignored if hill_param is specified.
        Default is 'Bouillon'.
    hill_param : list, optional
        Parameters of the model
        list [c50p_BIS, c50r_BIS, gamma_BIS, beta_BIS, E0_BIS, Emax_BIS, Delay_BIS]:

        - **c50p_BIS**: Concentration at half effect for propofol effect on BIS (µg/mL).
        - **c50r_BIS**: Concentration at half effect for remifentanil effect on BIS (ng/mL). If it is equal to zero the interaction with remifentanil is not considered.
        - **gamma_BIS**: Slope coefficient for the BIS model.
        - **beta_BIS**: Interaction coefficient for the BIS model (beta_BIS = 0 signifies an additive interaction, beta_BIS > 0 indicates synergy).
        - **E0_BIS**: Initial BIS.
        - **Emax_BIS**: Max effect of the drugs on BIS.
        - **Delay_BIS**: Delay affecting the BIS (s)

        The default is None.
        If Delay_BIS is not provided it is assumed equal to 0.
    random : bool, optional
        Add uncertainties in the parameters. Ignored if hill_param is specified. The default is False.
    ts : float
        Sampling time, in s.
    truncated : float, optional
        If not None it correspond to the number of standard deviation after which the distribution are truncated for generating uncertain parameters. The default is None.    


    Attributes
    ----------
    c50p : float
        Concentration at half effect for propofol effect on BIS (µg/mL).
    c50r : float
        Concentration at half effect for remifentanil effect on BIS (ng/mL). If it is equal to zero the interaction with remifentanil is not considered.
    gamma : float
        Slope coefficient for the BIS  model.
    beta : float
        Interaction coefficient for the BIS model (beta_BIS = 0 signifies an additive interaction, beta_BIS > 0 indicates synergy).
    E0 : float
        Initial BIS.
    Emax : float
        Max effect of the drugs on BIS.
    bis_delay : float
         Delay time on the output of the BIS model (s)          
    hill_param : list
        Parameters of the model
        list [c50p_BIS, c50r_BIS, gamma_BIS, beta_BIS, E0_BIS, Emax_BIS, Delay_BIS]
    c50p_init : float
        Initial value of c50p, used for blood loss modelling.
    hill_model : str
        'Vanluchene'[Vanluchene2004]_, do not consider the synergistic effect of remifentanil.
        'Eleveld'[Eleveld2018]_, do not consider the synergistic effect of remifentanil.
        'Bouillon'[Bouillon2004]_, considers the synergistic effect of remifentanil (Minto-type).
        'Fuentes'[Fuentes2018]_, considers the synergistic effect of remifentanil (Greco-type).
        'Yumuk'[Yumuk2024]_, considers the synergistic effect of remifentanil (Greco-type).
    ts : float
        Sampling time, in s.    

    References
    ----------
    .. [Bouillon2004] T. W. Bouillon et al., “Pharmacodynamic Interaction between Propofol and Remifentanil
            Regarding Hypnosis, Tolerance of Laryngoscopy, Bispectral Index, and Electroencephalographic
            Approximate Entropy,” Anesthesiology, vol. 100, no. 6, pp. 1353–1372, Jun. 2004,
            doi: 10.1097/00000542-200406000-00006.
    .. [Vanluchene2004] A. L. G. Vanluchene et al., “Spectral entropy as an electroencephalographic measure
            of anesthetic drug effect: a comparison with bispectral index and processed midlatency auditory evoked
            response,” Anesthesiology, vol. 101, no. 1, pp. 34–42, Jul. 2004,
            doi: 10.1097/00000542-200407000-00008.
    .. [Eleveld2018] D. J. Eleveld, P. Colin, A. R. Absalom, and M. M. R. F. Struys,
            “Pharmacokinetic–pharmacodynamic model for propofol for broad application in anaesthesia and sedation”
            British Journal of Anaesthesia, vol. 120, no. 5, pp. 942–959, mai 2018, doi:10.1016/j.bja.2018.01.018. 
    .. [Fuentes2018] R. Fuentes et al. "Propofol pharmacokinetic and pharmacodynamic profile and its 
            electroencephalographic interaction with remifentanil in children." Pediatric Anesthesia 28.12 (2018): 
            1078-1086. doi: 10.1111/pan.13486 
    .. [Yumuk2024] E. Yumuk et al.  "Data-driven identification and comparison of full multivariable models 
            for propofol–remifentanil induced general anesthesia." Journal of Process Control 139 (2024): 103243.
            doi: 10.1016/j.jprocont.2024.103243

    """

    def __init__(self,
                 hill_model: str = 'Bouillon',
                 hill_param: Optional[list] = None,
                 random: Optional[bool] = False,
                 truncated: Optional[float] = None,
                 ts: float = 1, **kwargs):
        """
        Init the class.

        Returns
        -------
        None.

        """

        self.hill_model = hill_model
        self.ts = ts

        if hill_param is not None:  # Parameter given as an input
            if len(hill_param) == 7:
                self.c50p = hill_param[0]
                self.c50r = hill_param[1]
                self.gamma = hill_param[2]
                self.beta = hill_param[3]
                self.E0 = hill_param[4]
                self.Emax = hill_param[5]
                self.bis_delay = hill_param[6]
            elif len(hill_param) == 6:
                self.c50p = hill_param[0]
                self.c50r = hill_param[1]
                self.gamma = hill_param[2]
                self.beta = hill_param[3]
                self.E0 = hill_param[4]
                self.Emax = hill_param[5]
                self.bis_delay = 0
            else:
                raise ValueError("The model parameters provided are not valid")

        # Minto-type surface model parameters
        elif self.hill_model == 'Bouillon':
            # See [Bouillon2004] T. W. Bouillon et al., “Pharmacodynamic Interaction between Propofol and Remifentanil
            # Regarding Hypnosis, Tolerance of Laryngoscopy, Bispectral Index, and Electroencephalographic
            # Approximate Entropy,” Anesthesiology, vol. 100, no. 6, pp. 1353–1372, Jun. 2004,
            # doi: 10.1097/00000542-200406000-00006.

            # model parameters and their coefficient of variation
            self.c50p = 4.47
            cv_c50p = 0.182
            self.c50r = 19.3
            cv_c50r = 0.888
            self.gamma = 1.43
            cv_gamma = 0.304
            self.beta = 0
            cv_beta = 0
            self.E0 = 97.4
            cv_E0 = 0
            self.Emax = self.E0
            cv_Emax = 0
            self.bis_delay = 0

        elif self.hill_model == 'Vanluchene':
            # See [Vanluchene2004]  A. L. G. Vanluchene et al., “Spectral entropy as an electroencephalographic measure
            # of anesthetic drug effect: a comparison with bispectral index and processed midlatency auditory evoked
            # response,” Anesthesiology, vol. 101, no. 1, pp. 34–42, Jul. 2004,
            # doi: 10.1097/00000542-200407000-00008.

            # model parameters and their coefficient of variation
            self.c50p = 4.92
            cv_c50p = 0.34
            self.c50r = 0
            cv_c50r = 0
            self.gamma = 2.69
            cv_gamma = 0.32
            self.beta = 0
            cv_beta = 0
            self.E0 = 95.9
            cv_E0 = 0.04
            self.Emax = 87.5
            cv_Emax = 0.11
            self.bis_delay = 0

        elif self.hill_model == 'Eleveld':
            # [Eleveld2018] D. J. Eleveld, P. Colin, A. R. Absalom, and M. M. R. F. Struys,
            # “Pharmacokinetic–pharmacodynamic model for propofol for broad application in anaesthesia and sedation”
            # British Journal of Anaesthesia, vol. 120, no. 5, pp. 942–959, mai 2018, doi:10.1016/j.bja.2018.01.018.

            age = kwargs.get('age', -1)
            if age < 0:
                raise ValueError("Age is missing for the Eleveld PD model for propofol.")

            # reference patient
            AGE_ref = 35

            # function used in the model
            def faging(x): return np.exp(x * (age - AGE_ref))
            def fdelay(x): return 15 + np.exp(x * age)

            # model parameters and their coefficient of variation
            self.c50p = 3.08 * faging(-0.00635)
            cv_c50p = 0.523
            self.c50r = 0
            cv_c50r = 0
            self.gamma = 1.89
            cv_gamma = 0
            self.gamma_2 = 1.47
            cv_gamma = 0  # only used if c_propo > c50p
            self.beta = 0
            cv_beta = 0
            self.E0 = 93
            cv_E0 = 0
            self.Emax = self.E0
            cv_Emax = 0
            self.bis_delay = fdelay(0.0517)

        # Greco-type surface model parameters
        elif self.hill_model == 'Fuentes':
            # See [Fuentes2018]  Fuentes, Ricardo, et al.
            # "Propofol pharmacokinetic and pharmacodynamic profile and its electroencephalographic interaction
            # with remifentanil in children." Pediatric Anesthesia 28.12 (2018): 1078-1086.
            # doi: 10.1111/pan.13486

            # model parameters and their coefficient of variation
            self.c50p = 2.99
            cv_c50p = 0.354
            self.c50r = 21
            cv_c50r = 0
            self.gamma = 2.69
            cv_gamma = 0.445
            self.beta = 0
            cv_beta = 0
            self.E0 = 94
            cv_E0 = 0.05
            self.Emax = 94 * 0.81
            cv_Emax = np.sqrt(0.005**2 + 0.148**2)
            self.bis_delay = 0

        elif self.hill_model == 'Yumuk':
            # See [Yumuk2024] Yumuk, E., et al.  "Data-driven identification and comparison of full multivariable models
            # for propofol–remifentanil induced general anesthesia." Journal of Process Control 139 (2024): 103243.
            # doi: 10.1016/j.jprocont.2024.103243

            # model parameters and their coefficient of variation
            self.c50p = 7.66
            cv_c50p = 0.297
            self.c50r = 149.62
            cv_c50r = 0.545
            self.gamma = 4.07
            cv_gamma = 0.448
            self.beta = 15.03
            cv_beta = 0.539
            self.E0 = 93.97
            cv_E0 = 0.0112
            self.Emax = self.E0
            cv_Emax = 0
            self.bis_delay = 0

        if random and hill_param is None:
            # estimation of log normal standard deviation
            w_c50p = np.sqrt(np.log(1 + cv_c50p**2))
            w_c50r = np.sqrt(np.log(1 + cv_c50r**2))
            w_gamma = np.sqrt(np.log(1 + cv_gamma**2))
            w_beta = np.sqrt(np.log(1 + cv_beta**2))
            w_E0 = np.sqrt(np.log(1 + cv_E0**2))
            w_Emax = np.sqrt(np.log(1 + cv_Emax**2))

        if random and hill_param is None:
            if truncated is not None:
                self.c50p *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50p))
                self.c50r *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50r))
                self.beta *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_beta))
                self.gamma *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_gamma))
                self.E0 *= min(100, np.exp(truncnorm.rvs(-truncated, truncated, scale=w_E0)))
                self.Emax *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_Emax))
            else:
                self.c50p *= np.exp(np.random.normal(scale=w_c50p))
                self.c50r *= np.exp(np.random.normal(scale=w_c50r))
                self.beta *= np.exp(np.random.normal(scale=w_beta))
                self.gamma *= np.exp(np.random.normal(scale=w_gamma))
                self.E0 *= min(100, np.exp(np.random.normal(scale=w_E0)))
                self.Emax *= np.exp(np.random.normal(scale=w_Emax))

        self.hill_param = [self.c50p, self.c50r, self.gamma, self.beta, self.E0, self.Emax, self.bis_delay]
        self.c50p_init = self.c50p  # for blood loss modelling
        # Buffer of BIS values to simulate delay. Initialized at E0.
        # Approximated by excess
        self.bis_buffer = np.ones(int(np.ceil(self.bis_delay / self.ts))) * self.E0

    def compute_bis(self, c_es_propo, c_es_remi=None):
        """Compute BIS function from propofol (and optionally remifentanil) effect site concentration.

        If the BIS model chosen considers only the effect of propofol the effect site concentration of remifentanil is ignored.
        Inputs can be either nd.array or float, the format of the output will be the same as the input

        Parameters
        ----------
        c_es_propo : float
            Propofol effect site concentration µg/mL.
        c_es_remi : float, optional
            Remifentanil effect site concentration ng/mL. The default is 0.

        Returns
        -------
        BIS : float
            Bis value.

        """
        vect_input = isinstance(c_es_propo, np.ndarray)

        if c_es_remi is None:
            if vect_input:
                c_es_remi = np.zeros_like(c_es_propo)
            else:
                c_es_remi = 0

        up = c_es_propo / self.c50p
        if self.hill_model == 'Eleveld':
            if vect_input:
                gamma = np.where(c_es_propo <= self.c50p, self.gamma, self.gamma_2)
            else:
                gamma = self.gamma if c_es_propo <= self.c50p else self.gamma_2
            interaction = up
        else:
            gamma = self.gamma

        if self.c50r == 0:
            interaction = up
        elif self.hill_model in ['Bouillon']:
            up = c_es_propo / self.c50p
            ur = c_es_remi / self.c50r
            Phi = up / (up + ur + 1e-6)
            U_50 = 1 - self.beta * (Phi - Phi**2)
            interaction = (up + ur) / U_50
        else:
            # Use Greco-style interaction model
            up = c_es_propo / self.c50p
            ur = c_es_remi / self.c50r
            interaction = up + ur + self.beta * up * ur

        interaction_gamma = interaction ** gamma
        bis = self.E0 - self.Emax * interaction_gamma / (1 + interaction_gamma)

        return bis

    def one_step(self, c_es_propo: float, c_es_remi: Optional[float] = 0) -> float:
        """Compute one step time of the BIS model

        Parameters
        ----------
        c_es_propo : float
            Propofol effect site concentration (µg/mL).
        c_es_remi : float, optional
            Remifentanil effect site concentration (ng/mL). The default is 0.

        Returns
        -------
        BIS : float
            Bis value.

        """

        bis_temp = self.compute_bis(c_es_propo, c_es_remi)
        if len(self.bis_buffer) > 1:
            self.bis_buffer = np.roll(self.bis_buffer, -1)
            bis = self.bis_buffer[0]
            self.bis_buffer[-1] = float(bis_temp.item())
        else:
            bis = bis_temp

        return bis

    def full_sim(self, c_es_propo: np.ndarray, c_es_remi: Optional[np.ndarray] = None) -> np.ndarray:
        """ Simulate BIS model with a given input.

        Parameters
        ----------
        c_es_propo : np.ndarray
            List of propofol effect site concentrations (µg/ml).
        c_es_remi : np.ndarray, optional
            List of remifentanil effect site concentrations (ng/ml).

        Returns
        -------
        np.ndarray
            List of the output BIS values during the simulation.

        """
        if c_es_remi is not None:
            if len(c_es_propo) != len(c_es_remi):
                raise ValueError("Inputs must have the same lenght")
        else:
            c_es_remi = np.zeros(len(c_es_propo))

        BIS_output = np.ones(len(c_es_propo))
        for index in range(len(c_es_propo)):
            BIS_output[index] = self.one_step(c_es_propo[index], c_es_remi[index])

        return BIS_output

    def update_param_blood_loss(self, v_ratio: float):
        """Update PK coefficient to mimic a blood loss.

        Update the c50p parameters thanks to the blood volume ratio. The values are estimated from [Johnson2003]_.

        Parameters
        ----------
        v_loss : float
            blood volume as a fraction of init volume, 1 mean no loss, 0 mean 100% loss.

        Returns
        -------
        None.

        References
        ----------
        .. [Johnson2003]  K. B. Johnson et al., “The Influence of Hemorrhagic Shock on Propofol: A Pharmacokinetic
                and Pharmacodynamic Analysis,” Anesthesiology, vol. 99, no. 2, pp. 409–420, Aug. 2003,
                doi: 10.1097/00000542-200308000-00023.

        """
        self.c50p = self.c50p_init - 3 / 0.5 * (1 - v_ratio)

    def inverse_hill(self, BIS: float, c_es_remi: Optional[float] = 0) -> float:
        """Compute Propofol effect site concentration from BIS (and optionally Remifentanil effect site concentration if the BIS model chosen takes into acount interaction) .

        Parameters
        ----------
        BIS : float
            BIS value.
        cer : float, optional
            Effect site Remifentanil concentration (ng/mL). The default is 0.

        Returns
        -------
        cep : float
            Effect site Propofol concentration (µg/mL).

        """

        # Special case : no drug effect
        if np.isclose(BIS, self.E0, atol=1e-6):
            return 0.0

        # Propofol-only model
        if self.c50r == 0:
            # If the Eleveld model is selected select the slope according to
            # the value of the BIS. Ce50 is the value at which 50% of the Emax
            # is reached. So I check this condition on the BIS.

            if self.hill_model == 'Eleveld' and BIS < (self.E0 - (self.Emax / 2)):
                gamma = self.gamma_2
            else:
                gamma = self.gamma
            cep = self.c50p * ((self.E0 - BIS) / (self.Emax - self.E0 + BIS))**(1 / gamma)

            return cep

        # Propofol-remifentanil
        temp = (max(0, self.E0 - BIS) / (self.Emax - self.E0 + BIS))**(1 / self.gamma)
        Yr = c_es_remi / self.c50r
        # Minto type inversion
        if self.hill_model in ['Bouillon', 'Vanluchene', 'Eleveld']:
            temp = (max(0, self.E0 - BIS) / (self.Emax - self.E0 + BIS))**(1 / self.gamma)
            Yr = c_es_remi / self.c50r
            b = 3 * Yr - temp
            c = 3 * Yr**2 - (2 - self.beta) * Yr * temp
            d = Yr**3 - Yr**2 * temp

            p = np.poly1d([1, b, c, d])
            cep = np.nan

            real_root = 0
            try:
                for el in np.roots(p):
                    if np.real(el) == el and np.real(el) > 0:
                        real_root = np.real(el)
                        cep = real_root * self.c50p
                        break
            except Exception as e:
                print(f'bug: {e}')
                cep = np.nan
        # Greco type inversion
        else:
            try:
                numerator = temp - Yr
                denominator = 1 + self.beta * Yr
                cep = self.c50p * (numerator / denominator) if denominator != 0 else np.nan
            except Exception as e:
                print(f'bug: {e}')
        return cep

    def plot_surface(self):
        """Plot the 3D-Hill surface of the BIS related to Propofol and Remifentanil effect site concentration or the 2-D Hill curve of the BIS related to Propofol effect site concentration according to the BIS model chosen"""

        if self.c50r == 0:
            cep = np.linspace(0, 16, 17)
            if self.hill_model == 'Eleveld':
                bis = np.linspace(0, 16, 17)
                i = 0
                for value in cep:
                    bis[i] = self.compute_bis(value)
                    i = i + 1
            else:
                bis = self.compute_bis(cep)
            plt.figure()
            plt.plot(cep, bis)
            plt.xlabel('Propofol Ce [μg/mL]')
            plt.ylabel('BIS')
            plt.grid(True)
            plt.ylim(0, 100)
            plt.show()

        elif self.c50r != 0:
            cer = np.linspace(0, 8, 9)
            cep = np.linspace(0, 12, 13)
            cer, cep = np.meshgrid(cer, cep)
            effect = self.compute_bis(cep, cer)
            fig, ax = plt.subplots(subplot_kw={"projection": "3d"})
            surf = ax.plot_surface(cer, cep, effect, cmap=cm.jet, linewidth=0.1)
            ax.set_xlabel('Remifentanil Ce [ng/mL]')
            ax.set_ylabel('Propofol Ce [μg/mL]')
            ax.set_zlabel('BIS')
            ax.set_zlim(0, 100)
            ax.set_zticks(np.arange(0, 101, 10))
            fig.colorbar(surf, shrink=0.5, aspect=8)
            ax.view_init(20, 60, 0)
            plt.show()


class LOC_model:
    r"""Propofol + Remifentanil -> LOC (Loss of Consciousness) model (Greco-type interaction).

    The equation is:

    .. math:: LOC = \frac{U^\gamma}{1+U^\gamma}

    with the Greco-type surface response model:

    .. math:: U = U_p + U_r + \beta U_p U_r

    where 

    .. math:: U_p = \frac{C_{p,es}}{C_{p,50}}
    .. math:: U_r = \frac{C_{r,es}}{C_{r,50}}


    Parameters
    ----------
    hill_model : str, optional
        'Kern'[Kern2004]_, considers the synergistic effect of remifentanil (Greco-type surface model).
        'Mertens'[Mertens2003]_, considers the synergistic effect of remifentanil (Greco-type surface model).
        'Johnson'[Johnson2008]_, considers the synergistic effect of remifentanil (Greco-type surface model).
        Ignored if hill_param is specified.
        Default is 'Kern'.
    hill_param : list, optional
        Parameters of the model
        list [c50p_LOC, c50r_LOC, gamma_LOC, beta_LOC]:
        - **c50p_LOC**: Concentration at half effect for propofol effect on LOC (µg/mL).
        - **c50r_LOC**: Concentration at half effect for remifentanil effect on LOC (ng/mL).
        - **gamma_LOC**: Slope coefficient for the LOC model.
        - **beta_LOC**: Interaction coefficient for the LOC model (beta_LOC = 0 signifies an additive interaction, beta_LOC > 0 indicates synergy).
    random : bool, optional
        Add uncertainties in the parameters. Ignored if hill_param is specified. The default is False.
    ts : float
        Sampling time, in s.
    truncated : float, optional
        If not None it correspond to the number of standard deviation after which the distribution are truncated for generating uncertain parameters. The default is None.


    Attributes
    ----------
    c50p : float
        Concentration at half effect for propofol effect on LOC (µg/mL).
    c50r : float
        Concentration at half effect for remifentanil effect on LOC (ng/mL).
    gamma : float
        Slope coefficient for the LOC  model.
    beta : float
        Interaction coefficient for the LOC model (beta_LOC = 0 signifies an additive interaction, beta_LOC > 0 indicates synergy). 
    hill_param : list
        Parameters of the model
        list [c50p_LOC, c50r_LOC, gamma_LOC, beta_LOC]
    hill_model : str
        'Kern' [Kern2004]_, considers the synergistic effect of remifentanil (Greco-type).
        'Mertens' [Mertens2003]_, considers the synergistic effect of remifentanil (Greco-type).
        'Johnson' [Johnson2008]_, considers the synergistic effect of remifentanil (Greco-type).
    ts : float
        Sampling time, in s.    

    References
    ---------- 
    .. [Kern2004] S. E. Kern et al. "A response surface analysis of propofol-remifentanil pharmacodynamic 
            interaction in volunteers." Anesthesiology 100.6 (2004): 1373-1381. doi : 10.1097/00000542-200406000-00007
    .. [Mertens2003] M. J. Mertens et al. "Propofol reduces perioperative remifentanil requirements 
            in a synergistic manner: response surface modeling of perioperative remifentanil–propofol interactions." 
            Anesthesiology 99.2 (2003): 347-359. doi : 10.1097/00000542-200308000-00016
    .. [Johnson2008] K. B. Johnson et al. "Validation of remifentanil propofol response surfaces for sedation, 
            surrogates of surgical stimulus, and laryngoscopy in patients undergoing surgery." Anesthesia and 
            analgesia 106.2 (2008): 471. doi : 10.1213/ane.0b013e3181606c62

    """

    def __init__(self,
                 hill_model: str = 'Kern',
                 hill_param: Optional[list] = None,
                 random: Optional[bool] = False,
                 ts: float = 1,
                 truncated: Optional[float] = None):
        """
        Init the class.

        Returns
        -------
        None.

        """

        self.hill_model = hill_model
        self.ts = ts

        if hill_param is not None:  # Parameter given as an input
            if len(hill_param) == 4:
                self.c50p = hill_param[0]
                self.c50r = hill_param[1]
                self.gamma = hill_param[2]
                self.beta = hill_param[3]
            else:
                raise ValueError("The model parameters provided are not valid")

        elif self.hill_model == 'Kern':
            # See [Kern2004]  Kern, Steven E., et al.
            # "A response surface analysis of propofol-remifentanil pharmacodynamic interaction in volunteers."
            # Anesthesiology 100.6 (2004): 1373-1381. doi : 10.1097/00000542-200406000-00007

            # model parameters and their coefficient of variation
            self.c50p = 1.80
            cv_c50p = 0.06 / 1.80
            self.c50r = 12.5
            cv_c50r = 0.53 / 12.5
            self.gamma = 3.76
            cv_gamma = 0
            self.beta = 5.1
            cv_beta = 0

        elif self.hill_model == 'Mertens':
            # See [Mertens2003]  Mertens, Martijn J., et al.
            # "Propofol reduces perioperative remifentanil requirements in a synergistic manner: response surface
            # modeling of perioperative remifentanil–propofol interactions." Anesthesiology 99.2 (2003): 347-359.
            # doi : 10.1097/00000542-200308000-00016

            # model parameters and their coefficient of variation
            self.c50p = 2.92
            cv_c50p = 0.51 / 2.92
            self.c50r = 5.15
            cv_c50r = 2.80 / 5.15
            self.gamma = 3.88
            cv_gamma = 1.09 / 3.88
            self.beta = 0
            cv_beta = 0

        elif self.hill_model == 'Johnson':
            # See [Johnson2008] Johnson, Ken B., et al.
            # "Validation of remifentanil propofol response surfaces for sedation, surrogates of surgical stimulus,
            # and laryngoscopy in patients undergoing surgery." Anesthesia and analgesia 106.2 (2008): 471.
            # doi : 10.1213/ane.0b013e3181606c62

            # model parameters and their coefficient of variation
            self.c50p = 2.20
            cv_c50p = 0
            self.c50r = 33.1
            cv_c50r = 0
            self.gamma = 5.00
            cv_gamma = 0
            self.beta = 3.60
            cv_beta = 0

        if random and hill_param is None:
            # estimation of log normal standard deviation
            w_c50p = np.sqrt(np.log(1 + cv_c50p**2))
            w_c50r = np.sqrt(np.log(1 + cv_c50r**2))
            w_gamma = np.sqrt(np.log(1 + cv_gamma**2))
            w_beta = np.sqrt(np.log(1 + cv_beta**2))

        if random and hill_param is None:
            if truncated is not None:
                self.c50p *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50p))
                self.c50r *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50r))
                self.beta *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_beta))
                self.gamma *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_gamma))
            else:
                self.c50p *= np.exp(np.random.normal(scale=w_c50p))
                self.c50r *= np.exp(np.random.normal(scale=w_c50r))
                self.beta *= np.exp(np.random.normal(scale=w_beta))
                self.gamma *= np.exp(np.random.normal(scale=w_gamma))

        self.hill_param = [self.c50p, self.c50r, self.gamma, self.beta]

    def compute_loc(self, c_es_propo, c_es_remi):
        """Compute LOC function (0-1) from propofol and remifentanil effect site concentration.

        LOC = 0  means fully awake, LOC = 1 deep LOC


        Parameters
        ----------
        c_es_propo : float
            Propofol effect site concentration µg/mL.
        c_es_remi : float, optional
            Remifentanil effect site concentration ng/mL.

        Returns
        -------
        LOC : float
            LOC value.
        """
        up = np.asarray(c_es_propo, dtype=float) / self.c50p
        ur = np.asarray(c_es_remi, dtype=float) / self.c50r
        interaction = up + ur + self.beta * up * ur
        interaction_gamma = interaction ** self.gamma
        loc = interaction_gamma / (1 + interaction_gamma)

        return loc

    def plot_surface(self):
        """Plot the 3D-Hill surface of the LOC related to Propofol and Remifentanil effect site concentration"""
        cer = np.linspace(0, 8, 9)   # ng/mL
        cep = np.linspace(0, 12, 13)    # µg/mL
        cer, cep = np.meshgrid(cer, cep)
        effect = self.compute_loc(cep, cer)
        fig, ax = plt.subplots(subplot_kw={"projection": "3d"})
        surf = ax.plot_surface(cer, cep, effect, cmap=cm.jet, linewidth=0.1)
        ax.set_xlabel('Remifentanil Ce [ng/mL]')
        ax.set_ylabel('Propofol Ce [µg/mL]')
        ax.set_zlabel('LOC (0–1)')
        ax.set_zlim(0, 1)
        fig.colorbar(surf, shrink=0.5, aspect=8)
        ax.view_init(15, -70)
        plt.show()


class TOL_model():
    r"""Hierarchical model to link drug effect site concentration to Tolerance of Laringoscopy.

    The equation are:


    .. math:: postopioid = preopioid * \left(1 - \frac{C_{r,es}^{\gamma_r}}{C_{r,es}^{\gamma_r} + (C_{r,50} preopioid)^{\gamma_r}}\right)
    .. math:: TOL = \frac{C_{p,es}^{\gamma_p}}{C_{p,es}^{\gamma_p} + (C_{p,50} postopioid)^{\gamma_p}}

    Parameters
    ----------
    model : str, optional
        Only 'Bouillon' is available. Ignored if model_param is specified. The default is 'Bouillon'.
    model_param : list, optional
        Model parameters, model_param = [c50p, c50p, gammaP, gammaR, Preopioid intensity].
        The default is None.
    random : bool, optional
        Add uncertainties in the parameters. Ignored if model_param is specified. The default is False.
    truncated : float, optional
        If not None it correspond to the number of standard deviation after which the distribution are truncated for generating uncertain parameters. The default is None.

    Attributes
    ----------
    c50p : float
        Concentration at half effect for propofol effect on BIS (µg/mL).
    c50r : float
        Concentration at half effect for remifentanil effect on BIS (ng/mL).
    gamma_p : float
        Slope of the Hill function for propofol effect on TOL.
    gamma_r : float
        Slope of the Hill function for remifentanil effect on TOL.
    pre_intensity : float
        Preopioid intensity.

    """

    def __init__(
            self,
            model: Optional[str] = 'Bouillon',
            model_param: Optional[list] = None,
            random: Optional[bool] = False,
            truncated: Optional[float] = None,
    ):
        """
        Init the class.

        Returns
        -------
        None.

        """
        if model == "Bouillon":
            # See [Bouillon2004] T. W. Bouillon et al., “Pharmacodynamic Interaction between Propofol and Remifentanil
            # Regarding Hypnosis, Tolerance of Laryngoscopy, Bispectral Index, and Electroencephalographic
            # Approximate Entropy,” Anesthesiology, vol. 100, no. 6, pp. 1353–1372, Jun. 2004,
            # doi: 10.1097/00000542-200406000-00006.
            self.c50p = 8.04
            self.c50r = 1.07
            self.gamma_r = 0.97
            self.gamma_p = 5.1
            self.pre_intensity = 1.05  # Here we choose to use the value from laringoscopy

            cv_c50p = 0
            cv_c50r = 0.26
            cv_gamma_p = 0.9
            cv_gamma_r = 0.23
            cv_pre_intensity = 0
            w_c50p = np.sqrt(np.log(1 + cv_c50p**2))
            w_c50r = np.sqrt(np.log(1 + cv_c50r**2))
            w_gamma_p = np.sqrt(np.log(1 + cv_gamma_p**2))
            w_gamma_r = np.sqrt(np.log(1 + cv_gamma_r**2))
            w_pre_intensity = np.sqrt(np.log(1 + cv_pre_intensity**2))

        if random and model_param is None:
            if truncated is not None:
                self.c50p *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50p))
                self.c50r *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50r))
                self.gamma_r *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_gamma_p))
                self.gamma_p *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_gamma_r))
                self.pre_intensity *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_pre_intensity))
            else:
                self.c50p *= np.exp(np.random.normal(scale=w_c50p))
                self.c50r *= np.exp(np.random.normal(scale=w_c50r))
                self.gamma_r *= np.exp(np.random.normal(scale=w_gamma_p))
                self.gamma_p *= np.exp(np.random.normal(scale=w_gamma_r))
                self.pre_intensity *= np.exp(np.random.normal(scale=w_pre_intensity))

    def compute_tol(self, c_es_propo: float, c_es_remi: float) -> float:
        """Return TOL from Propofol and Remifentanil effect site concentration.

        Compute the output of the Hirarchical model to predict TOL
        from Propofol and Remifentanil effect site concentration.
        TOL = 1 mean very relaxed and will tolerate laryngoscopy while TOL = 0 mean fully awake and will not tolerate it.

        Parameters
        ----------
        cep : float
            Propofol effect site concentration µg/mL.
        cer : float
            Remifentanil effect site concentration ng/mL

        Returns
        -------
        TOL : float
            TOL value.

        """
        post_opioid = self.pre_intensity * (1 - fsig(c_es_remi, self.c50r * self.pre_intensity, self.gamma_r))
        tol = fsig(c_es_propo, self.c50p * post_opioid, self.gamma_p)
        return tol

    def plot_surface(self):
        """Plot the 3D-Hill surface of the BIS related to Propofol and Remifentanil effect site concentration."""
        cer = np.linspace(0, 20, 50)
        cep = np.linspace(0, 8, 50)
        cer, cep = np.meshgrid(cer, cep)
        effect = self.compute_tol(cep, cer)
        fig, ax = plt.subplots(subplot_kw={"projection": "3d"})
        surf = ax.plot_surface(cer, cep, effect, cmap=cm.jet, linewidth=0.1)
        ax.set_xlabel('Remifentanil')
        ax.set_ylabel('Propofol')
        ax.set_zlabel('TOL')
        fig.colorbar(surf, shrink=0.5, aspect=8)
        ax.view_init(12, -72)
        plt.show()


class Hemo_meca_PD_model:
    r"""This class implements the mechanically based model of Haemodynamics proposed in [Su2023]_.

    See section :ref:`hemodynamics` for detail about the model implemented here. 

    Parameters
    ----------
    age : float
        Age of the patient in years.
    ts : float
        Sampling time in seconds.
    model : str, optional
        Model to use, 'Su' (see [Su2023]_) and 'VitalDB' (see :ref:`disurbance_identification`) are available. The default is 'Su'.
    nore_model : str, optional
        Model to use for norepinephrine, 'Beloeil' and 'Oualha' are available. The default is 'Beloeil'.
    random : bool, optional
        Add uncertainties in the parameters. The default is False.
    hr_base : float, optional
        Baseline heart rate (bpm). The default is None, which will use the value from the Su model.
    sv_base : float, optional
        Baseline stroke volume (mL). The default is None, which will use the value from the Su model.
    map_base : float, optional
        Baseline mean arterial pressure (mmHg). The default is None, which will use the value from the Su model.
    truncated : bool, optional
        Use truncated normal distribution (between [-3, +3] std) for the random parameters. The default is False.

    References
    ----------
    .. [Su2023] H. Su, J. V. Koomen, D. J. Eleveld, M. M. R. F. Struys, and P. J. Colin,
            “Pharmacodynamic mechanism-based interaction model for the haemodynamic effects of remifentanil
            and propofol in healthy volunteers,” *British Journal of Anaesthesia*, vol. 131, no. 2,
            pp. 222–233, Aug. 2023. doi:10.1016/j.bja.2023.04.043.

    .. [Beloeil2005] H. Beloeil, J.-X. Mazoit, D. Benhamou, and J. Duranteau,
            “Norepinephrine kinetics and dynamics in septic shock and trauma patients,”
            *BJA: British Journal of Anaesthesia*, vol. 95, no. 6, pp. 782–788, Dec. 2005.
            doi:10.1093/bja/aei259.

    .. [Oualha2014] M. Oualha et al., “Population pharmacokinetics and haemodynamic effects of norepinephrine
            in hypotensive critically ill children,” *British Journal of Clinical Pharmacology*,
            vol. 78, no. 4, pp. 886–897, 2014. doi:10.1111/bcp.12412.
    """

    def __init__(self,
                 age: float,
                 ts: float,
                 model: str = 'Su',
                 nore_model: str = 'Beloeil',
                 random: bool = False,
                 truncated: bool = False,
                 hr_base: float = None,
                 sv_base: float = None,
                 map_base: float = None,
                 ):
        """
        Initialize the class.

        Returns
        -------
        None.

        """
        self.ts = ts

        if model == 'Su' or model == 'VitalDB':
            self.sv_base = 82.2
            self.hr_base = 56.1
            self.tpr_base = 0.0163
            self.k_out = 0.072 / 60  # (1/s)
            self.fb = -0.661
            self.hr_sv = 0.312
            self.k_ltde = 0.067 / 60  # (1/s)
            self.ltde_sv = 0.0899
            self.ltde_hr = 0.121
            self.c50_propo_tpr = 3.21  # (µg/ml)
            self.emax_propo_tpr = -0.778  # (%)
            self.gamma_propo_tpr = 1.83
            self.c50_propo_sv = 0.44  # (µg/ml)
            emax_propo_sv_type = -0.154
            self.emax_propo_sv = emax_propo_sv_type * np.exp(0.0333 * (age - 35))
            self.age_max_sv = 0.033
            self.c50_remi_tpr = 4.59  # (ng/ml)
            self.emax_remi_tpr = -1
            self.sl_remi_hr = 0.0327  # (ng/ml)
            self.sl_remi_sv = 0.0581  # (ng/ml)
            self.int_hr = -0.119  # (ng/ml)
            self.c50_int_hr = 0.20  # (µg/ml)
            self.int_tpr = 1
            self.int_sv = -0.212  # (ng/ml)

            if model == 'VitalDB':
                self.sv_base = 93.1 / (1 + self.ltde_hr)
                self.hr_base = 74.7 / (1 + self.ltde_sv)
                self.tpr_base = 102 / (74.7 * 93.1)
                # update model param
                self.int_hr = -0.097
                self.emax_propo_tpr = -0.03
                self.fb = -0.5

            if hr_base is not None:
                self.hr_base = hr_base / (1 + self.ltde_hr)
                self.sv_base = sv_base / (1 + self.ltde_sv)
                self.tpr_base = map_base / (hr_base * sv_base)

            # uncertainties values
            self.w_block1_mu = [0, 0, 0]
            self.w_block1_cov = [  # in order tpr, sv, hr
                [0.0528, -0.0244, -0.0233],
                [-0.0244, 0.0328, 0],
                [-0.0233, 0, 0.0242]
            ]
            if model == "VitalDB":
                self.w_block1_cov = np.array([[0.09085827, -0.07249175, -0.01973828],
                                              [-0.07249175,  0.09255021, -0.00040959],
                                              [-0.01973828, -0.00040959,  0.02315553]])

            self.w_block2_mu = [0, 0]
            self.w_block2_cov = [[0.00382, 0.00329], [0.00329, 0.00868]]

            self.w_c50_propo_tpr = np.sqrt(0.44)
            self.w_emax_remi_tpr = np.sqrt(0.449)

        else:
            raise ValueError("only Su and VitalDB are implemented as model")
        if nore_model == 'Beloeil':
            # see H. Beloeil, J.-X. Mazoit, D. Benhamou, and J. Duranteau, “Norepinephrine kinetics and dynamics
            # in septic shock and trauma patients,” BJA: British Journal of Anaesthesia,
            # vol. 95, no. 6, pp. 782–788, Dec. 2005, doi: 10.1093/bja/aei259.
            self.emax_nore_map = 98.7
            self.c50_nore_map = 7.04
            self.gamma_nore_map = 1.8
            w_emax_nore_map = 0
            w_c50_nore_map = np.sqrt(np.log(1+1.64/self.c50_nore_map**2))
            w_gamma_nore_map = 0
        elif nore_model == 'Oualha':
            # see M. Oualha et al., “Population pharmacokinetics and haemodynamic effects of norepinephrine
            # in hypotensive critically ill children,” British Journal of Clinical Pharmacology,
            # vol. 78, no. 4, pp. 886–897, 2014, doi: 10.1111/bcp.12412.
            self.emax_nore_map = 32
            self.c50_nore_map = 4.11
            self.gamma_nore_map = 1
            w_emax_nore_map = 0
            w_c50_nore_map = 0.09
            w_gamma_nore_map = 0
        self.k_effect = 0.0002  # (1/s)

        if random:
            if truncated is not None:  # truncated normal to 3 standard deviations
                # lognormal distribution
                in_range = False
                while not in_range:
                    eta_values_block1 = np.random.multivariate_normal(self.w_block1_mu, self.w_block1_cov, size=1)[0]
                    check_1 = np.abs(eta_values_block1[0] - self.w_block1_mu[0]
                                     ) <= truncated*np.sqrt(self.w_block1_cov[0][0])
                    check_2 = np.abs(eta_values_block1[1] - self.w_block1_mu[1]
                                     ) <= truncated*np.sqrt(self.w_block1_cov[1][1])
                    check_3 = np.abs(eta_values_block1[2] - self.w_block1_mu[2]
                                     ) <= truncated*np.sqrt(self.w_block1_cov[2][2])
                    if check_1 and check_2 and check_3:
                        in_range = True

                self.tpr_base *= np.exp(eta_values_block1[0])
                self.sv_base *= np.exp(eta_values_block1[1])
                self.hr_base *= np.exp(eta_values_block1[2])
                self.c50_propo_tpr *= np.exp(truncnorm.rvs(-truncated, truncated, self.w_c50_propo_tpr))
                # normal distribution
                self.emax_remi_tpr += truncnorm.rvs(-truncated, truncated, scale=self.w_emax_remi_tpr)

                in_range = False
                while not in_range:
                    eta_values_block2 = np.random.multivariate_normal(self.w_block2_mu, self.w_block2_cov, size=1)[0]
                    if np.abs(eta_values_block2[0] - self.w_block2_mu[0]) <= 3*np.sqrt(self.w_block2_cov[0][0]) and np.abs(eta_values_block2[1] - self.w_block2_mu[1]) <= 3*np.sqrt(self.w_block2_cov[1][1]):
                        in_range = True
                self.sl_remi_hr += eta_values_block2[0]
                self.sl_remi_sv += eta_values_block2[1]

                self.emax_nore_map *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_emax_nore_map))
                self.c50_nore_map *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_c50_nore_map))
                self.gamma_nore_map *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_gamma_nore_map))
            else:  # infinite support normal distribution
                eta_values_block1 = np.random.multivariate_normal(self.w_block1_mu, self.w_block1_cov, size=1)[0]
                self.tpr_base *= np.exp(eta_values_block1[0])
                self.sv_base *= np.exp(eta_values_block1[1])
                self.hr_base *= np.exp(eta_values_block1[2])

                self.c50_propo_tpr *= np.exp(np.random.normal(self.w_c50_propo_tpr))
                # normal distribution
                self.emax_remi_tpr += np.random.normal(0, self.w_emax_remi_tpr)

                eta_values_block2 = np.random.multivariate_normal(self.w_block2_mu, self.w_block2_cov, size=1)[0]
                self.sl_remi_hr += eta_values_block2[0]
                self.sl_remi_sv += eta_values_block2[1]

                self.emax_nore_map *= np.exp(np.random.normal(scale=w_emax_nore_map))
                self.c50_nore_map *= np.exp(np.random.normal(scale=w_c50_nore_map))
                self.gamma_nore_map *= np.exp(np.random.normal(scale=w_gamma_nore_map))

        self.k_in_tpr = self.k_out * self.tpr_base
        self.k_in_sv = self.k_out * self.sv_base
        self.k_in_hr = self.k_out * self.hr_base

        self.x = np.array([
            self.tpr_base,
            self.sv_base,
            self.hr_base,
            self.sv_base * self.ltde_sv,
            self.hr_base * self.ltde_hr,
        ])

        self.x_effect = np.array([
            self.tpr_base,
            self.sv_base,
            self.hr_base,
            self.sv_base * self.ltde_sv,
            self.hr_base * self.ltde_hr,
        ])
        self.flag_nore_used = False
        self.flag_blood_loss = False

        self.abase_sv = self.sv_base * (1 + self.ltde_sv)
        self.abase_hr = self.hr_base * (1 + self.ltde_hr)
        self.base_map = self.tpr_base * self.abase_sv * self.abase_hr

        self.previous_cp_propo = 0
        self.previous_cp_remi = 0

        self.time_id = 0

    def continuous_dynamic(
            self,
            x: np.ndarray,
            u: np.ndarray
    ) -> np.ndarray:
        """Define the continuous dynamic of the haemodynamic system.

        For implementation details see supplementary material nb 6 of the paper of Su and co-authors.

        Parameters
        ----------
        x : np.ndarray
            state array composed of tpr, sv, hr, ltde_sv, ltde_hr.
        u: np.ndarray
            u = [cp_propo, cp_remi, map_wanted, sv_wanted, tpr_stim, sv_stim, hr_stim], plasma concentration of propofol (µg/ml) and remifentanil (ng/ml), map wanted (for norepinephrine simulation), sv_wanted (for blood loss simulation) and stimuli value for stimuli application. 

        Returns
        -------
        d x / dt : np.ndarray
            temporal derivative of the state array.
        """

        # compute drug effect
        cp_propo = u[0]
        cp_remi = u[1]
        map_wanted = u[2]
        sv_wanted = u[3]
        tpr_stim = u[4]
        sv_stim = u[5]
        hr_stim = u[6]

        eff_propo_tpr = (self.emax_propo_tpr + self.int_tpr * fsig(cp_remi, self.c50_remi_tpr, 1)) * \
            fsig(cp_propo, self.c50_propo_tpr, self.gamma_propo_tpr)
        eff_remi_sv = (self.sl_remi_sv + self.int_sv * fsig(cp_propo, self.c50_propo_sv, 1)) * cp_remi
        eff_remi_hr = (self.sl_remi_hr + self.int_hr * fsig(cp_propo, self.c50_int_hr, 1)) * cp_remi
        eff_propo_sv = self.emax_propo_sv * fsig(cp_propo, self.c50_propo_sv, 1)
        eff_remi_tpr = self.emax_remi_tpr * fsig(cp_remi, self.c50_remi_tpr, 1)

        # saturate the effects
        eff_propo_tpr = np.clip(eff_propo_tpr, -0.999, 0.999)
        eff_remi_sv = np.clip(eff_remi_sv, -0.999, 0.999)
        eff_remi_hr = np.clip(eff_remi_hr, -0.999, 0.999)
        eff_propo_sv = np.clip(eff_propo_sv, -0.999, 0.999)
        eff_remi_tpr = np.clip(eff_remi_tpr, -0.999, 0.999)

        # compute apparent values
        dtpr = x[0] + tpr_stim
        dsv = x[1] + x[3] + sv_stim
        dhr = x[2] + x[4] + hr_stim

        a_sv = dsv * (1 - self.hr_sv * np.log(dhr / self.abase_hr))
        a_map = a_sv * dhr * dtpr

        rmap = a_map / self.base_map

        sv = x[1]
        hr = x[2]
        tpr_dot = self.k_in_tpr * rmap**self.fb * (1 + eff_propo_tpr) - \
            self.k_out * x[0] * (1 - eff_remi_tpr)
        if map_wanted > 0:
            tpr_dot += (map_wanted - a_map) * self.k_effect
        sv_dot_star = self.k_in_sv * rmap**self.fb * (1 + eff_propo_sv) - self.k_out * sv * (1 - eff_remi_sv)
        if sv_wanted > 0:
            sv_dot_star += (sv_wanted - a_sv) * self.k_effect * 10000
        hr_dot_star = self.k_in_hr * rmap**self.fb - self.k_out * hr * (1 - eff_remi_hr)

        if u[0] > 0:  # apply the time dependant function only if anesthesia as started.
            ltde_sv_dot = -self.k_ltde * x[3]
            ltde_hr_dot = -self.k_ltde * x[4]
        else:
            ltde_sv_dot = 0
            ltde_hr_dot = 0

        return np.array([tpr_dot, sv_dot_star, hr_dot_star, ltde_sv_dot, ltde_hr_dot])

    def continuous_dynamic_sys(self, t, x, u):
        """ Same as continuous_dynamic but with time as first arguments (for scipy simulation)."""
        return self.continuous_dynamic(x, u)

    def output_function(self, x: np.ndarray, dist: np.ndarray = np.zeros(3)) -> np.ndarray:
        """Compute final signals value from state and disturbance value.

        Parameters
        ----------
        x : np.ndarray
            state of the system

        Returns
        -------
        np.ndarray
            Total peripheral resistance (mmHg min/ mL), Stroke volume (ml),
            heart rate (beat / min), mean arterial pressure (mmHg),
            cardiac output (L/min)
        """
        tpr = x[0] + dist[0]
        sv = x[1] + x[3] + dist[1]
        hr = x[2] + x[4] + dist[2]
        sv = sv * (1 - self.hr_sv * np.log(hr / self.abase_hr))
        map = tpr * sv * hr
        co = hr * sv / 1000  # fro mL/min to L/min
        return np.array([tpr, sv, hr, map, co])

    def nore_map_effect(self, cp_nore: float):
        """Compute Norepinephrine effect on MAP.

        Parameters
        ----------
        c_nore : float
            Concentration of Norepinephrine (ng/mL)
        """

        return self.emax_nore_map * fsig(cp_nore, self.c50_nore_map, self.gamma_nore_map)

    def one_step(
            self,
            cp_propo: float = 0,
            cp_remi: float = 0,
            cp_nore: float = 0,
            v_ratio: float = 1,
            disturbances: list = None,
    ) -> np.ndarray:
        """Compute one step time of the hemodynamic system.

        It use Runge Kutta 4 to compute the non-linear integration.

        Parameters
        ----------
        c_propo : float
            current plasma concentration of propofol (µg/ml), default is 0.
        cp_remi : float
            current plasma concentration of remifentanil (ng/ml), default is 0.
        cp_nore : float
            current plasma concentration of norepinephrine (ng/ml), default is 0.
        v_ratio : float
            blood volume as a fraction of init volume, 1 mean no loss, 0 mean 100% loss, default is 1.
        disturbances : list
            disturbance on TPR, SV, and HR (in this order). The default is [0]*3.

        Return
        -------

        """
        if disturbances is None:
            disturbances = [0]*3
        c_propo_sim = (self.previous_cp_propo + cp_propo) / 2
        c_remi_sim = (self.previous_cp_remi + cp_remi) / 2
        # run computation for model without nore effect and without blood loss
        results = solve_ivp(
            self.continuous_dynamic_sys,
            t_span=np.array([0, self.ts]),
            t_eval=np.array([0, self.ts]),
            y0=self.x,
            args=([c_propo_sim, c_remi_sim, 0, 0] + disturbances,),
        )
        self.x = results.y[:, -1]

        if (self.flag_nore_used or cp_nore > 0) and not self.flag_blood_loss:
            if not self.flag_blood_loss:
                self.flag_nore_used = True
            if v_ratio != 1:
                print("Warning: norepinephrine effect is not computed with blood loss")
            map_no_nore = self.output_function(self.x, disturbances)[3]
            map_wanted = map_no_nore + self.nore_map_effect(cp_nore)
            # run computation for model with nore effect
            results_w_nore = solve_ivp(
                self.continuous_dynamic_sys,
                t_span=np.array([0, self.ts]),
                y0=self.x_effect,
                args=([c_propo_sim, c_remi_sim, map_wanted, 0] + disturbances,),
            )
            self.x_effect = results_w_nore.y[:, -1]
        elif (v_ratio < 1 or self.flag_blood_loss) and not self.flag_nore_used:
            if not self.flag_blood_loss:
                self.flag_blood_loss = True
            if cp_nore > 0:
                print("Warning: norepinephrine effect is not computed with blood loss")
            sv_no_blood_loss = self.output_function(self.x, disturbances)[1]
            sv_wanted = sv_no_blood_loss * v_ratio
            results_blood_loss = solve_ivp(
                self.continuous_dynamic_sys,
                t_span=np.array([0, self.ts]),
                y0=self.x_effect,
                args=([c_propo_sim, c_remi_sim, 0, sv_wanted] + disturbances,),
            )
            self.x_effect = results_blood_loss.y[:, -1]
        else:
            self.x_effect = self.x.copy()

        self.previous_cp_propo = cp_propo
        self.previous_cp_remi = cp_remi
        output = self.output_function(self.x_effect, disturbances)
        return output  # tpr, sv, hr, map, co

    def full_sim(self,
                 cp_propo: np.ndarray,
                 cp_remi: np.ndarray,
                 cp_nore: np.ndarray,
                 disturbances: np.ndarray = None,
                 x0: Optional[np.ndarray] = None
                 ) -> np.ndarray:
        """ Simulate hemodynamic model with a given input.

        Parameters
        ----------
        c_propo : np.ndarray
            list of plasma concentration of propofol (µg/ml).
        cp_remi : np.ndarray
            list of plasma concentration of remifentanil (ng/ml).
        cp_nore : np.ndarray
            list of plasma concentration of norepinephrine (ng/ml).
        disturbance : np.ndarray
            N*3 array of distrubance signal for TPR, SV and HR.
        x0 : np.ndarray, optional
            Initial state. The default is None.

        Returns
        -------
        np.ndarray
            List of the output value during the simulation.
        """
        if len(cp_remi) != len(cp_propo) or len(cp_remi) != len(cp_nore):
            raise ValueError("inputs must have the same lenght")
        if x0 is not None:
            self.x = x0
            self.x_no_nore = x0
        if disturbances is None:
            disturbances = np.zeros((len(cp_propo), 3))

        y_output = np.zeros((len(cp_propo), 5))
        for index in range(len(cp_propo)):
            y_output[index, :] = self.one_step(
                cp_propo[index],
                cp_remi[index],
                cp_nore[index],
                disturbances=list(disturbances[index, :])
            )

        return y_output

    def state_at_equilibrium(
            self,
            cp_propo_eq: float = 0,
            cp_remi_eq: float = 0,
            cp_nore_eq: float = 0,
            disturbances: list = None,
            x0: np.ndarray = None,
    ) -> np.ndarray:
        """Solve the problem f(x,u)=0 for the continuous dynamique with a given u.

        Parameters
        ----------
        c_propo : float
            plasma concentration of propofol at equilibrium (µg/ml).
        cp_remi : float
            plasma concentration of remifentanil  at equilibrium (ng/ml).
        cp_nore : float
            plasma concentration of norepinephrine  at equilibrium (ng/ml).
        disturbance: list
            disturbance on TPR, SV, and HR (in this order). The default is [0]*3.
        x0 : np.ndarray, optional
            Initial state. The default is None.

        Returns
        -------
        np.ndarray
            List of the output value at equilibrium.
        """
        if disturbances is None:
            disturbances = [0]*3
        if x0 is None:
            x0 = self.x
        # solve equilibrium without nore
        x = cas.MX.sym('x', 5)
        dx = cas.vertcat(*self.continuous_dynamic(x, [cp_propo_eq, cp_remi_eq, 0, 0] + disturbances))
        F_root = cas.rootfinder('F_root', 'newton', {'x': x, 'g': dx})
        sol = F_root(x0=x0)
        x_no_nore = sol['x'].full().flatten()
        self.x_eq = x_no_nore

        # if nore is used, solve equilibrium with nore
        if cp_nore_eq > 0:
            output_no_nore = self.output_function(x_no_nore, dist=disturbances)
            map_eq = output_no_nore[3] + self.nore_map_effect(cp_nore_eq)
            # solve equilibrium with nore
            x = cas.MX.sym('x', 5)
            dx = cas.vertcat(*self.continuous_dynamic(x, [cp_propo_eq, cp_remi_eq, map_eq, 0] + disturbances))
            # map_nore = self.output_function(x)[3]
            # dx[0] = (map_nore - map_eq)**2
            F_root = cas.rootfinder('F_root', 'newton', {'x': x, 'g': dx})
            sol = F_root(x0=x0)

            x_eq_out = sol['x'].full().flatten()
        else:
            x_eq_out = x_no_nore

        output = self.output_function(x_eq_out, dist=disturbances)
        self.x_eq_w_nore = x_eq_out

        return output

    def initialized_at_given_concentration(
            self,
            cp_propo_eq: float = 0,
            cp_remi_eq: float = 0,
            cp_nore_eq: float = 0
    ) -> None:
        """Initialize the haemodynamic model at a given concentration.

        Parameters
        ----------
        c_propo : float
            plasma concentration of propofol at equilibrium (µg/ml).
        cp_remi : float
            plasma concentration of remifentanil  at equilibrium (ng/ml).
        cp_nore : float
            plasma concentration of norepinephrine  at equilibrium (ng/ml).

        Returns
        -------
        None
            The haemodynamic model is initialized at the given concentration.
        """

        # compute the state at equilibrium
        _ = self.state_at_equilibrium(cp_propo_eq, cp_remi_eq, cp_nore_eq)
        # initialize the haemodynamic model
        self.x_effect = self.x_eq_w_nore
        self.x = self.x_eq
        self.previous_cp_propo = cp_propo_eq
        self.previous_cp_remi = cp_remi_eq


class TOF_model:
    r"""Model to link Atracurium effect site concentration to train-of-four (TOF).

    The equation is:

    .. math:: TOF = \frac{100*C_{50}^\gamma}{C_{50}^\gamma + C_e^\gamma}

    Parameters
    ----------
    hill_model : str, optional
        'Weatherley' [Weatherley1983]_       
        Ignored if hill_param is specified.
        Default is 'Weatherley'.
    hill_param : dict, optional
        Parameters of the model:

        - **'c50'**: Half effect concentration (µg/mL).
        - **'gamma'**: Stepness of the Hill curve.

        If it is not provided default values are used.



    Attributes
    ----------
    c50p : float
        Concentration at half effect for atracurium effect on TOF (µg/mL).
    gamma : float
        slope coefficient for the Hill curve.
    hill_model : str
        'Weatherley' [Weatherley1983]_

    References
    ----------
    .. [Weatherley1983] B. Weatherley et al., "Pharmacokinetics, Pharmacodynamics and Dose-Response Relationship of Atracurium Administered i.v." 
            British Journal of Anesthesia, vol. 55, Suppl. 1, pp. 39S-45S, Jan. 1983.

    """

    def __init__(self, hill_model: str = 'Weatherley',
                 hill_param: Optional[dict] = None):
        """
        Init the class.

        Returns
        -------
        None.

        """
        if hill_param is None:
            hill_param = {}
        self.hill_model = hill_model

        if self.hill_model == 'Weatherley':

            self.C50 = hill_param.get('C50', 0.625)
            self.gamma = hill_param.get('gamma', 4.25)

    def compute_tof(self, Ce):
        """Compute TOF from atracurium effect site concentration.

        Parameters
        ----------
        Ce : float
            Atracurium effect site concentration (µg/mL).


        Returns
        -------
        TOF : float
            TOF value.

        """

        if self.hill_model == 'Weatherley':
            tof = (100 * self.C50**self.gamma) / (self.C50**self.gamma + Ce**self.gamma)

        return tof

    def plot_surface(self):
        """Plot the 2D-Hill curve of the train-of-four (TOF) related to Atracurium effect site concentration"""
        ce = np.linspace(0, 8, 100)
        tof = self.compute_tof(ce)
        plt.figure()
        plt.plot(ce, tof)
        plt.xlabel('Atracurium Ce [μg/mL]')
        plt.ylabel('TOF')
        plt.grid(True)
        plt.ylim(0, 100)
        plt.show()
