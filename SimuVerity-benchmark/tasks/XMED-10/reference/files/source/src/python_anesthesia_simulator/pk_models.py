# Standard import
import copy
from typing import Optional
import math

# Third party imports
import numpy as np
from scipy.signal import lsim, StateSpace
from scipy.stats import truncnorm


class CompartmentModel:
    """PKmodel class modelize the PK model of propofol, remifentanil or norepinephrine drug. Simulate the drug distribution in the body.

    Use a 6 compartement model for propofol, a 5 compartement model for remifentanil
    and a 1 compartement model for norepinephrine.
    The model is a LTI model with the form:

    .. math::  x(k+1)= Ax(k) + Bu(k)
    .. math::  y(k) = Cx(k)

    The state vector is the concentration of the drug in each compartement in the following order:

    * blood, muscles, fat, BIS effect-site, MAP effect-site 1, MAP effect-site 2 for propofol;
    * blood, muscles, fat, BIS effect-site, MAP effect-site 1 for remifentanil;
    * blood for norepinephrine;

    The output of the model is:

    * the BIS effect-site concentration for propofol and remifentanil;
    * the blood concentration for norepinephrine;

    Parameters
    ----------
    Patient_characteristic: list
        Patient_characteristic = [age (yr), height(cm), weight(kg), sex(0: female, 1: male)]
    lbm : float
        lean body mass index.
    drug : str
        can be "Propofol", "Remifentanil" or "Norepinephrine".
    model : str, optional
        Could be "Schnider"[Schnider1999]_, "Marsh_initial"[Marsh1991]_, "Marsh_modified"[Struys2000]_,
        "Shuttler"[Schuttler2000]_ or "Eleveld"[Eleveld2018]_ for Propofol.
        "Minto"[Minto1997]_, or "Eleveld"[Eleveld2017]_ for Remifentanil.
        "Beloeil"[Beloeil2005]_, "Oualha"[Oualha2014]_, or "Li"[Li2024]_ for Norepinephrine.
        The default is "Schnider" for Propofol, "Minto" for Remifentanil, and "Beloeil" for Norepinephrine.
    ts : float, optional
        Sampling time, in s. The default is 1.
    random : bool, optional
        bool to introduce uncertainties in the model. The default is False.
    x0 : np.ndarray, optional
        Initial concentration of the compartement model. The default is np.zeros((len(A), 1)).
    opiate : bool, optional
        For Elelevd model for propofol, specify if their is a co-administration of opiate (Remifentantil)
        in the same time. The default is True.
    measurement : str, optional
        For Elelevd model for propofol, specify the measuremnt place for blood concentration.
        Can be either 'arterial' or 'venous'. The default is 'arterial'.
    truncated : float, optional
        If not None it correspond to the number of standard deviation after which the distribution are truncated for generating uncertain parameters. The default is None.

    Attributes
    ----------
    ts : float
        Sampling time, in s.
    drug : str
        can be "Propofol", "Remifentanil" or "Norepinephrine".
    A_init : np.ndarray
        Initial value of the matrix A.
    B_init : np.ndarray
        Initial value of the matrix B.
    v1 : float
        Volume of the first compartement.
    u_endo : float.
        Endogenous production of drug (µg/s).
    self.u_lag : float.
        Lag time in the input of the model (s).
    continuous_sys : control.StateSpace
        Continuous state space model.
    discrete_sys : control.StateSpace
        Discrete state space model.
    x : np.ndarray
        State vector.
    y : np.ndarray
        Output vector (hypnotic effect site concentration).

    References
    ----------
    .. [Schnider1999] T. W. Schnider et al., “The Influence of Age on Propofol Pharmacodynamics,”
            Anesthesiology, vol. 90, no. 6, pp. 1502-1516., Jun. 1999, doi: 10.1097/00000542-199906000-00003.
    .. [Marsh1991] B. Marsh, M. White, N. morton, and G. N. C. Kenny,
            “Pharmacokinetic model Driven Infusion of Propofol in Children,”
            BJA: British Journal of Anaesthesia, vol. 67, no. 1, pp. 41–48, Jul. 1991, doi: 10.1093/bja/67.1.41.
    .. [Struys2000] M. M. R. F. Struys et al., “Comparison of Plasma Compartment versus  Two Methods for Effect
            Compartment–controlled Target-controlled Infusion for Propofol,”
            Anesthesiology, vol. 92, no. 2, p. 399, Feb. 2000, doi: 10.1097/00000542-200002000-00021.
    .. [Schuttler2000] J. Schüttler and H. Ihmsen, “Population Pharmacokinetics of Propofol: A Multicenter Study,”
            Anesthesiology, vol. 92, no. 3, pp. 727–738, Mar. 2000, doi: 10.1097/00000542-200003000-00017.
    .. [Eleveld2018] D. J. Eleveld, P. Colin, A. R. Absalom, and M. M. R. F. Struys,
            “Pharmacokinetic–pharmacodynamic model for propofol for broad application in anaesthesia and sedation”
            British Journal of Anaesthesia, vol. 120, no. 5, pp. 942–959, mai 2018, doi:10.1016/j.bja.2018.01.018.
    .. [Minto1997] C. F. Minto et al., “Influence of Age and Gender on the Pharmacokinetics
            and Pharmacodynamics of Remifentanil: I. Model Development,”
            Anesthesiology, vol. 86, no. 1, pp. 10–23, Jan. 1997, doi: 10.1097/00000542-199701000-00004.
    .. [Eleveld2017] D. J. Eleveld et al., “An Allometric Model of Remifentanil Pharmacokinetics and Pharmacodynamics,”
            Anesthesiology, vol. 126, no. 6, pp. 1005–1018, juin 2017, doi: 10.1097/ALN.0000000000001634.
    .. [Beloeil2005] H. Beloeil, J.-X. Mazoit, D. Benhamou, and J. Duranteau, “Norepinephrine kinetics and dynamics
            in septic shock and trauma patients,” BJA: British Journal of Anaesthesia,
            vol. 95, no. 6, pp. 782–788, Dec. 2005, doi: 10.1093/bja/aei259.
    .. [Oualha2014] M. Oualha et al., “Population pharmacokinetics and haemodynamic effects of norepinephrine
            in hypotensive critically ill children,” British Journal of Clinical Pharmacology,
            vol. 78, no. 4, pp. 886–897, 2014, doi: 10.1111/bcp.12412.
    .. [Li2024] Y. Li et al., “Population Pharmacokinetic Modelling of Norepinephrine
            in Healthy Volunteers Prior to and During General Anesthesia,” Clin Pharmacokinet,
            vol. 63, no. 11, pp. 1597–1608, Nov. 2024, doi: 10.1007/s40262-024-01430-y.

    """

    def __init__(self, Patient_characteristic: list,
                 lbm: float,
                 drug: str,
                 model: str = None,
                 ts: float = 1,
                 random: Optional[bool] = False,
                 x0: Optional[np.ndarray] = None,
                 opiate: Optional[bool] = True,
                 measurement: Optional[str] = "arterial",
                 truncated: Optional[float] = None):
        """Init the class."""
        self.ts = ts
        age = Patient_characteristic[0]
        height = Patient_characteristic[1]
        weight = Patient_characteristic[2]
        sex = Patient_characteristic[3]
        self.u_endo = 0  # endogenous production of drug (used for Norepinephrine)
        self.u_lag = 0  # lag in seconds
        self.model = model
        if drug == "Propofol":
            if self.model is None:
                self.model = 'Schnider'
            if self.model == 'Schnider':
                # see T. W. Schnider et al., “The Influence of Age on Propofol Pharmacodynamics,”
                # Anesthesiology, vol. 90, no. 6, pp. 1502-1516., Jun. 1999, doi: 10.1097/00000542-199906000-00003.

                # Clearance Rates [l/min]
                cl1 = 1.89 + 0.0456 * (weight - 77) - 0.0681 * \
                    (lbm - 59) + 0.0264 * (height - 177)
                cl2 = 1.29 - 0.024 * (age - 53)
                cl3 = 0.836
                # Volume of the compartmente [l]
                v1 = 4.27
                v2 = 18.9 - 0.391 * (age - 53)
                v3 = 238
                # drug amount transfer rates [1/min]
                ke0 = 0.456

                # variability
                cv_v1 = v1*0.0404
                cv_v2 = v2*0.01
                cv_v3 = v3*0.1435
                cv_cl1 = cl1*0.1005
                cv_cl2 = cl2*0.01
                cv_cl3 = cl3*0.1179
                cv_ke = ke0*0.42  # The real value seems to be not available in the article

                # estimation of log normal standard deviation
                w_v1 = np.sqrt(np.log(1+cv_v1**2))
                w_v2 = np.sqrt(np.log(1+cv_v2**2))
                w_v3 = np.sqrt(np.log(1+cv_v3**2))
                w_cl1 = np.sqrt(np.log(1+cv_cl1**2))
                w_cl2 = np.sqrt(np.log(1+cv_cl2**2))
                w_cl3 = np.sqrt(np.log(1+cv_cl3**2))
                w_ke0 = np.sqrt(np.log(1+cv_ke**2))

            elif self.model == 'Marsh_initial' or self.model == 'Marsh_modified':
                # see B. Marsh, M. White, N. morton, and G. N. C. Kenny,
                # “Pharmacokinetic model Driven Infusion of Propofol in Children,”
                # BJA: British Journal of Anaesthesia, vol. 67, no. 1, pp. 41–48, Jul. 1991, doi: 10.1093/bja/67.1.41.

                v1 = 0.228 * weight
                v2 = 0.463 * weight
                v3 = 2.893 * weight
                cl1 = 0.119 * v1
                cl2 = 0.112 * v1
                cl3 = 0.042 * v1

                if self.model == 'Marsh_initial':
                    ke0 = 0.26
                else:
                    ke0 = 1.2

                # variability
                # estimation of log normal standard deviation
                # not given in the paper so estimated at 100% for each variable
                w_v1 = np.sqrt(np.log(1+1**2))
                w_v2 = np.sqrt(np.log(1+1**2))
                w_v3 = np.sqrt(np.log(1+1**2))
                w_cl1 = np.sqrt(np.log(1+1**2))
                w_cl2 = np.sqrt(np.log(1+1**2))
                w_cl3 = np.sqrt(np.log(1+1**2))
                w_ke0 = np.sqrt(np.log(1+1**2))

            elif self.model == 'Schuttler':
                # J. Schüttler and H. Ihmsen, “Population Pharmacokinetics of Propofol: A Multicenter Study,”
                # Anesthesiology, vol. 92, no. 3, pp. 727–738, Mar. 2000, doi: 10.1097/00000542-200003000-00017.

                theta = [None,  # just to get same index than in the paper
                         1.44,  # Cl1 [l/min]
                         9.3,  # v1ref [l]
                         2.25,  # Cl2 [l/min]
                         44.2,  # v2ref [l]
                         0.92,  # Cl3 [l/min]
                         266,  # v3ref [l]
                         0.75,
                         0.62,
                         0.61,
                         0.045,
                         0.55,
                         0.71,
                         -0.39,
                         -0.40,
                         1.61,
                         2.02,
                         0.73,
                         -0.48]

                v1 = theta[2] * (weight/70)**theta[12] * (age/30)**theta[13]
                v2 = theta[4] * (weight/70)**theta[9]
                v3 = theta[6]
                if age <= 60:
                    cl1 = theta[1] * (weight/70)**theta[7]
                else:
                    cl1 = theta[1] * (weight/70)**theta[7] - (age-60)*theta[10]
                cl2 = theta[3] * (weight/70)**theta[8]
                cl3 = theta[5] * (weight/70)**theta[11]

                # no PD model so we reuse Marsh modified one
                ke0 = 1.2

                # variability
                cv_v1 = 0.400
                cv_v2 = 0.548
                cv_v3 = 0.469
                cv_cl1 = 0.374
                cv_cl2 = 0.519
                cv_cl3 = 0.509
                # estimation of log normal standard deviation
                w_v1 = np.sqrt(np.log(1+cv_v1**2))
                w_v2 = np.sqrt(np.log(1+cv_v2**2))
                w_v3 = np.sqrt(np.log(1+cv_v3**2))
                w_cl1 = np.sqrt(np.log(1+cv_cl1**2))
                w_cl2 = np.sqrt(np.log(1+cv_cl2**2))
                w_cl3 = np.sqrt(np.log(1+cv_cl3**2))
                w_ke0 = np.sqrt(np.log(1+1**2))

            elif self.model == 'Eleveld':
                # see D. J. Eleveld, P. Colin, A. R. Absalom, and M. M. R. F. Struys,
                # “Pharmacokinetic–pharmacodynamic model for propofol for broad application in anaesthesia and sedation”
                # British Journal of Anaesthesia, vol. 120, no. 5, pp. 942–959, mai 2018, doi:10.1016/j.bja.2018.01.018.

                # reference patient
                AGE_ref = 35
                WGT_ref = 70
                HGT_ref = 1.7
                PMA_ref = (40+AGE_ref*52)/52  # not born prematurely and now 35 yo
                BMI_ref = WGT_ref/HGT_ref**2
                GDR_ref = 1  # 1 male, 0 female

                theta = [None,                    # just to get same index than in the paper
                         6.2830780766822,       # V1ref [l]
                         25.5013145036879,      # V2ref [l]
                         272.8166615043603,     # V3ref [l]
                         1.7895836588902,       # Clref [l/min]
                         1.7500983738779,       # Q2ref [l/min]
                         1.1085424008536,       # Q3ref [l/min]
                         0.191307,              # Typical residual error
                         42.2760190602615,      # CL maturation E50
                         9.0548452392807,       # CL maturation slope [weeks]
                         -0.015633,             # Smaller V2 with age
                         -0.00285709,           # Lower CL with age
                         33.5531248778544,      # Weight for 50 % of maximal V1 [kg]
                         -0.0138166,            # Smaller V3 with age
                         68.2767978846832,      # Maturation of Q3 [weeks]
                         2.1002218877899,       # CLref (female) [l/min]
                         1.3042680471360,       # Higher Q2 for maturation of Q3
                         1.4189043652084,       # V1 venous samples (children)
                         0.6805003109141]       # Higer Q2 venous samples

                # function used in the model
                def faging(x): return np.exp(x * (age - AGE_ref))
                def fsig(x, C50, gam): return x**gam/(C50**gam + x**gam)
                def fcentral(x): return fsig(x, theta[12], 1)

                def fal_sallami(sexX, weightX, ageX, bmiX):
                    if sexX:
                        return (0.88 + (1-0.88)/(1+(ageX/13.4)**(-12.7)))*(9270*weightX)/(6680+216*bmiX)
                    else:
                        return (1.11 + (1 - 1.11)/(1+(ageX/7.1)**(-1.1)))*(9270*weightX)/(8780+244*bmiX)

                PMA = age + 40/52
                BMI = weight/(height/100)**2

                fCLmat = fsig(PMA * 52, theta[8], theta[9])
                fCLmat_ref = fsig(PMA_ref*52, theta[8], theta[9])
                fQ3mat = fsig(PMA * 52, theta[14], 1)
                fQ3mat_ref = fsig(PMA_ref * 52, theta[14], 1)
                fsal = fal_sallami(sex, weight, age, BMI)
                fsal_ref = fal_sallami(GDR_ref, WGT_ref, AGE_ref, BMI_ref)

                if opiate:
                    def fopiate(x): return np.exp(x*age)
                else:
                    def fopiate(x): return 1

                # reference: male, 70kg, 35 years and 170cm

                v1 = theta[1] * fcentral(weight)/fcentral(WGT_ref)
                if measurement == "venous":
                    v1 = v1 * (1 + theta[17] * (1 - fcentral(weight)))
                v2 = theta[2] * weight/WGT_ref * faging(theta[10])
                v2ref = theta[2]
                v3 = theta[3] * fsal/fsal_ref * fopiate(theta[13])
                v3ref = theta[3]
                cl1 = (sex*theta[4] + (1-sex)*theta[15]) * (weight/WGT_ref)**0.75 * \
                    fCLmat/fCLmat_ref * fopiate(theta[11])

                cl2 = theta[5]*(v2/v2ref)**0.75 * (1 + theta[16] * (1 - fQ3mat))
                if measurement == "venous":
                    cl2 = cl2*theta[18]

                cl3 = theta[6] * (v3/v3ref)**0.75 * fQ3mat/fQ3mat_ref
                if measurement == "venous":
                    ke0 = 1.24*(weight/70)**(-0.25)
                else:
                    ke0 = 0.146*(weight/70)**(-0.25)

                # Coeff variability
                cv_v1 = v1*0.917
                cv_v2 = v2*0.871
                cv_v3 = v3*0.904
                cv_cl1 = cl1*0.551
                cv_cl2 = cl2*0.643
                cv_cl3 = cl3*0.482

                # log normal standard deviation
                w_v1 = np.sqrt(0.610)
                w_v2 = np.sqrt(0.565)
                w_v3 = np.sqrt(0.597)
                w_cl1 = np.sqrt(0.265)
                w_cl2 = np.sqrt(0.346)
                w_cl3 = np.sqrt(0.209)
                w_ke0 = np.sqrt(0.702)

        elif drug == "Remifentanil":
            if self.model is None:
                self.model = 'Minto'
            if self.model == 'Minto':
                #  see C. F. Minto et al., “Influence of Age and Gender on the Pharmacokinetics
                # and Pharmacodynamics of Remifentanil: I. Model Development,”
                # Anesthesiology, vol. 86, no. 1, pp. 10–23, Jan. 1997, doi: 10.1097/00000542-199701000-00004.

                # Clearance Rates [l/min]
                cl1 = 2.6 - 0.0162 * (age - 40) + 0.0191 * (lbm - 55)
                cl2 = 2.05 - 0.0301 * (age - 40)
                cl3 = 0.076 - 0.00113 * (age - 40)

                # Volume of the compartmente [l]
                v1 = 5.1 - 0.0201 * (age-40) + 0.072 * (lbm - 55)
                v2 = 9.82 - 0.0811 * (age-40) + 0.108 * (lbm-55)
                v3 = 5.42

                ke0 = 0.595 - 0.007 * (age - 40)  # [1/min]

                # variability
                cv_v1 = 0.26
                cv_v2 = 0.29
                cv_v3 = 0.66
                cv_cl1 = 0.14
                cv_cl2 = 0.36
                cv_cl3 = 0.41
                cv_ke = 0.68

                # estimation of log normal standard deviation
                w_v1 = np.sqrt(np.log(1+cv_v1**2))
                w_v2 = np.sqrt(np.log(1+cv_v2**2))
                w_v3 = np.sqrt(np.log(1+cv_v3**2))
                w_cl1 = np.sqrt(np.log(1+cv_cl1**2))
                w_cl2 = np.sqrt(np.log(1+cv_cl2**2))
                w_cl3 = np.sqrt(np.log(1+cv_cl3**2))
                w_ke0 = np.sqrt(np.log(1+cv_ke**2))

            elif self.model == 'Eleveld':
                # see D. J. Eleveld et al., “An Allometric Model of Remifentanil Pharmacokinetics and Pharmacodynamics,”
                # Anesthesiology, vol. 126, no. 6, pp. 1005–1018, juin 2017, doi: 10.1097/ALN.0000000000001634.

                # function used in the model
                def faging(x): return np.exp(x * (age - 35))
                def fsig(x, C50, gam): return x**gam/(C50**gam + x**gam)

                def fal_sallami(sexX, weightX, ageX, bmiX):
                    if sexX:
                        return (0.88 + (1-0.88)/(1+(ageX/13.4)**(-12.7)))*(9270*weightX)/(6680+216*bmiX)
                    else:
                        return (1.11 + (1 - 1.11)/(1+(ageX/7.1)**(-1.1)))*(9270*weightX)/(8780+244*bmiX)

                # reference patient
                AGE_ref = 35
                WGT_ref = 70
                HGT_ref = 1.7
                PMA_ref = (40+AGE_ref*52)/52  # not born prematurely and now 35 yo
                BMI_ref = WGT_ref/HGT_ref**2
                GDR_ref = 1  # 1 male, 0 female

                BMI = weight/(height/100)**2

                SIZE = (fal_sallami(sex, weight, age, BMI)/fal_sallami(GDR_ref, WGT_ref, AGE_ref, BMI_ref))

                theta = [None,      # Juste to have the same index as in the paper
                         2.88,
                         -0.00554,
                         -0.00327,
                         -0.0315,
                         0.470,
                         -0.0260]

                KMAT = fsig(weight, theta[1], 2)
                KMATref = fsig(WGT_ref, theta[1], 2)
                if sex:
                    KSEX = 1
                else:
                    KSEX = 1+theta[5]*fsig(age, 12, 6)*(1-fsig(age, 45, 6))

                v1ref = 5.81
                v1 = v1ref * SIZE * faging(theta[2])
                V2ref = 8.882
                v2 = V2ref * SIZE * faging(theta[3])
                V3ref = 5.03
                v3 = V3ref * SIZE * faging(theta[4])*np.exp(theta[6]*(weight - WGT_ref))
                cl1ref = 2.58
                cl2ref = 1.72
                cl3ref = 0.124
                cl1 = cl1ref * SIZE**0.75 * (KMAT/KMATref)*KSEX*faging(theta[3])
                cl2 = cl2ref * (v2/V2ref)**0.75 * faging(theta[2]) * KSEX
                cl3 = cl3ref * (v3/V3ref)**0.75 * faging(theta[2])

                ke0 = 1.09 * faging(-0.0289)

                # log normal standard deviation
                w_v1 = np.sqrt(0.104)
                w_v2 = np.sqrt(0.115)
                w_v3 = np.sqrt(0.810)
                w_cl1 = np.sqrt(0.0197)
                w_cl2 = np.sqrt(0.0547)
                w_cl3 = np.sqrt(0.285)
                w_ke0 = np.sqrt(1.26)

        elif drug == 'Norepinephrine':
            if self.model is None:
                self.model = 'Beloeil'  # set defaut value
            if self.model == 'Beloeil':
                # see H. Beloeil, J.-X. Mazoit, D. Benhamou, and J. Duranteau, “Norepinephrine kinetics and dynamics
                # in septic shock and trauma patients,” BJA: British Journal of Anaesthesia,
                # vol. 95, no. 6, pp. 782–788, Dec. 2005, doi: 10.1093/bja/aei259.

                v1 = 8.840
                cl1 = 59.6 / 30  # suppose SAPS II = 30 ()

                w_v1 = np.sqrt(np.log(1+1.63/v1**2))
                w_cl1 = np.sqrt(np.log(1+0.974/cl1**2))
            elif self.model == 'Oualha':
                # see M. Oualha et al., “Population pharmacokinetics and haemodynamic effects of norepinephrine
                # in hypotensive critically ill children,” British Journal of Clinical Pharmacology,
                # vol. 78, no. 4, pp. 886–897, 2014, doi: 10.1111/bcp.12412.

                v1 = 0.08 * weight
                cl1 = 0.11 * weight**(3/4)
                self.u_endo = 0.052 * weight**(3/4) / 60

                w_v1 = 0
                w_cl1 = 0.36
                w_u_endo = 1.21
            elif self.model == "Li":
                # see Y. Li et al., “Population Pharmacokinetic Modelling of Norepinephrine
                # in Healthy Volunteers Prior to and During General Anesthesia,” Clin Pharmacokinet,
                # vol. 63, no. 11, pp. 1597–1608, Nov. 2024, doi: 10.1007/s40262-024-01430-y.

                self._c_prop_base = 3.53
                c_prop = self._c_prop_base  # assume a concentration of propofol of 3.53 mg/mL
                self._prop_coeff = -3.57
                cl1 = 2.1 * np.exp(-0.377/100*(age-35)) * (weight/70)**0.75   # L/min
                v1 = 2.4 * (weight/70)  # L
                cl2 = 0.6*(weight/70)**0.75  # L/min
                v2 = 3.6 * (weight/70)  # L
                self.u_endo = 497.7 * (weight/70)**0.75 / 60 / 1000  # Convert to µg/s
                self.u_lag = 13.7 * (weight/70)**0.25

                w_v1 = np.sqrt(np.log(1+(44.5/100)**2))
                w_cl1 = np.sqrt(np.log(1+(10.6/100)**2))
                w_cl2 = 0
                w_v2 = np.sqrt(np.log(1+(40.4/100)**2))
                w_prop_effect = np.sqrt(np.log(1+(266.2/100)**2))
                w_u_endo = np.sqrt(np.log(1+(30.4/100)**2))

        if drug == 'Propofol':
            if random:
                if self.model == 'Marsh':
                    print("Warning: the standard deviation of the Marsh model are not know," +
                          " it is set to 100% for each variable")
                if truncated is not None:
                    v1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v1))
                    v2 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v2))
                    v3 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v3))
                    cl1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl1))
                    cl2 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl2))
                    cl3 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl3))
                    ke0 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_ke0))
                else:
                    v1 *= np.exp(np.random.normal(scale=w_v1))
                    v2 *= np.exp(np.random.normal(scale=w_v2))
                    v3 *= np.exp(np.random.normal(scale=w_v3))
                    cl1 *= np.exp(np.random.normal(scale=w_cl1))
                    cl2 *= np.exp(np.random.normal(scale=w_cl2))
                    cl3 *= np.exp(np.random.normal(scale=w_cl3))
                    ke0 *= np.exp(np.random.normal(scale=w_ke0))
            # drug amount transfer rates [1/min]
            k10 = cl1 / v1
            k12 = cl2 / v1
            k13 = cl3 / v1
            k21 = cl2 / v2
            k31 = cl3 / v3

            # Matrices system definition
            A = np.array([[-(k10 + k12 + k13), k12, k13, 0],
                          [k21, -k21, 0, 0],
                          [k31, 0, -k31, 0],
                          [ke0, 0, 0, -ke0]])/60  # 1/s

            B = np.transpose(np.array([[1/v1, 0, 0, 0]]))  # 1/L
            C = np.array([[0, 0, 0, 1]])
            D = np.array([[0]])

        elif drug == 'Remifentanil':
            if random:
                if truncated is not None:
                    v1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v1))
                    v2 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v2))
                    v3 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v3))
                    cl1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl1))
                    cl2 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl2))
                    cl3 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl3))
                    ke0 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_ke0))
                else:
                    v1 *= np.exp(np.random.normal(scale=w_v1))
                    v2 *= np.exp(np.random.normal(scale=w_v2))
                    v3 *= np.exp(np.random.normal(scale=w_v3))
                    cl1 *= np.exp(np.random.normal(scale=w_cl1))
                    cl2 *= np.exp(np.random.normal(scale=w_cl2))
                    cl3 *= np.exp(np.random.normal(scale=w_cl3))
                    ke0 *= np.exp(np.random.normal(scale=w_ke0))

            # drug amount transfer rates [1/min]
            k10 = cl1 / v1
            k12 = cl2 / v1
            k13 = cl3 / v1
            k21 = cl2 / v2
            k31 = cl3 / v3

            # Matrices system definition
            A = np.array([[-(k10 + k12 + k13), k12, k13, 0],
                          [k21, -k21, 0, 0],
                          [k31, 0, -k31, 0],
                          [ke0, 0, 0, -ke0]])/60  # 1/s

            B = np.transpose(np.array([[1/v1, 0, 0, 0]]))  # 1/L
            C = np.array([[0, 0, 0, 1]])
            D = np.array([[0]])

        elif drug == 'Norepinephrine':
            if random:
                if truncated is not None:
                    v1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v1))
                    cl1 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl1))
                    if self.model == 'Oualha' or self.model == "Li":
                        self.u_endo *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_u_endo))
                    if self.model == "Li":
                        v2 *= np.exp(truncnorm.rvs(-truncated, truncated, scale=w_v2))
                        cl2 = np.exp(truncnorm.rvs(-truncated, truncated, scale=w_cl2))
                        self._prop_coeff += truncnorm.rvs(-truncated, truncated,
                                                          scale=w_prop_effect)  # additive uncertainty
                        cl1 *= np.exp(self._prop_coeff*(c_prop - self._c_prop_base))
                else:
                    v1 *= np.exp(np.random.normal(scale=w_v1))
                    cl1 *= np.exp(np.random.normal(scale=w_cl1))
                    if self.model == 'Oualha' or self.model == "Li":
                        self.u_endo *= np.exp(np.random.normal(scale=w_u_endo))
                    if self.model == "Li":
                        v2 *= np.exp(np.random.normal(scale=w_v2))
                        cl2 = np.exp(np.random.normal(scale=w_cl2))
                        self._prop_coeff += np.random.normal(scale=w_prop_effect)  # additive uncertainty
                        cl1 *= np.exp(self._prop_coeff*(c_prop - self._c_prop_base))
            if self.model == 'Beloeil' or self.model == "Oualha":  # first order model
                # drug amount transfer rates [1/min]
                k10 = cl1 / v1

                # Matrices system definition
                A = np.array([-k10])/60  # 1/s

                B = np.array([1/v1])  # 1/L
                C = np.array([1])
                D = np.array([0])
            elif self.model == "Li":  # second order model
                # drug amount transfer rates [1/min]
                k10 = cl1 / v1
                self._k12 = cl2 / v1
                k21 = cl2 / v2

                # Matrices system definition
                A = np.array([[-(k10 + self._k12), self._k12],
                              [k21, -k21]])/60  # 1/s
                B = np.transpose(np.array([[1/v1, 0]]))  # 1/L
                C = np.array([[1, 0]])
                D = np.array([[0]])

        self.A_init = A
        self.B_init = B
        self.v1 = v1
        self.drug = drug
        # Continuous system with blood concentration as output
        # self.continuous_sys = control.ss(A, B, C, D)
        self.continuous_sys = StateSpace(A, B, C, D)
        # Discretization of the system
        self.discretize_sys = self.continuous_sys.to_discrete(self.ts)

        # init output
        if x0 is None:
            x0 = np.zeros((len(A), 1))  # np.ones(len(A))*1e-3
            if self.model == 'Oualha' or self.model == "Li":
                x0 = np.ones((len(A), 1)) * self.u_endo / cl1 * 60
        self.x = x0
        self.y = np.dot(C, self.x)

        self.u_buffer = np.zeros(int(np.round(self.u_lag / self.ts))+1)

    def one_step(self, u: float) -> list:
        """Simulate one step of PK model.

        .. math:: x^+ = Ax + Bu
        .. math:: y = Cx

        Parameters
        ----------
        u : float
            Infusion rate (mg/s for Propofol, µg/s for Remifentanil and Norepinephrine).

        Returns
        -------
        numpy array
            Actual effect site concentration (µg/mL for Propofol and ng/mL
            for Remifentanil and Norepinephrine).

        """
        self.u_buffer = np.roll(self.u_buffer, -1)
        self.u_buffer[-1] = u
        self.x = self.discretize_sys.A @ self.x + self.discretize_sys.B * (self.u_buffer[0]+self.u_endo)
        self.y = self.discretize_sys.C @ self.x + self.discretize_sys.D * (self.u_buffer[0]+self.u_endo)

        return self.y[0, 0]

    def full_sim(self, u: np.ndarray, x0: Optional[np.ndarray] = None, interp=False) -> list:
        """ Simulate PK model with a given input.

        Parameters
        ----------
        u : list
            Infusion rate (mg/s for Propofol, µg/s for Remifentanil and Norepinephrine).
        x0 : numpy array, optional
            Initial state. The default is None.
        interp : bool, optional
            Whether to use zero-order-hold (False, the default) or linear (True) interpolation for the input array.

        Returns
        -------
        numpy array
            List of the states value during the simulation.
            (µg/mL for Propofol and ng/mL for Remifentanil and Norepinephrine).

        """
        u = np.roll(u, int(np.round(self.u_lag / self.ts)))
        u[:int(np.round(self.u_lag / self.ts))] = 0
        if x0 is None:
            x0 = np.zeros(len(self.A_init))
            if self.model == 'Oualha':
                cl1 = - self.continuous_sys.A[0, 0]*60 * self.v1
                x0 = np.ones(len(self.A_init)) * self.u_endo / cl1 * 60
            elif self.model == 'Li':
                cl1 = (- self.continuous_sys.A[0, 0]*60 - self._k12)*self.v1
                x0 = np.ones(len(self.A_init)) * self.u_endo / cl1 * 60
        t = np.ones_like(u)*self.ts
        t[0] = 0
        t = np.cumsum(t)
        _, _, x_lsim = lsim(
            self.continuous_sys,
            T=t,
            U=u+self.u_endo,
            X0=x0,
            interp=interp
        )
        x = x_lsim.T
        return x

    def update_param_CO(self, CO_ratio: float):
        """Update PK coefficient with a linear function of Cardiac output value.

        Parameters
        ----------
        CO_ratio : float
            Ratio of Current CO relatively to initial CO.

        Returns
        -------
        None.

        """
        coeff = 1
        Anew = copy.deepcopy(self.A_init)
        if self.drug == 'Propofol' or self.drug == 'Remifentanil':
            Anew[:3, :3] = coeff * Anew[:3, :3] * CO_ratio
        else:
            Anew = Anew * coeff * CO_ratio
        # Continuous system with blood concentration as output
        self.continuous_sys = StateSpace(Anew, self.continuous_sys.B, self.continuous_sys.C, self.continuous_sys.D)
        # Discretization of the system
        self.discretize_sys = self.continuous_sys.to_discrete(self.ts)

    def update_param_blood_loss(self, v_ratio: float, CO_ratio: float):
        """Update PK coefficient to mimic a blood loss.

            Update the blood volume compartment

        Parameters
        ----------
        v_ratio : float
            blood volume as a fraction of init volume, 1 mean no loss, 0 mean 100% loss.
        CO_ratio : float
            Ratio of Current CO relatively to initial CO.

        Returns
        -------
        None.

        """
        coeff = 1
        Anew = copy.deepcopy(self.A_init)
        Bnew = copy.deepcopy(self.B_init)
        if self.drug == 'Propofol' or self.drug == 'Remifentanil':
            Anew[0, 0] /= v_ratio
            Anew[0, 1] /= v_ratio
            Anew[0, 2] /= v_ratio
            Anew[:3, :3] = coeff * Anew[:3, :3] * CO_ratio
        else:
            Anew /= v_ratio
            Anew = Anew * coeff * CO_ratio
        Bnew /= v_ratio

        # Continuous system with blood concentration as output
        self.continuous_sys = StateSpace(Anew, Bnew, self.continuous_sys.C, self.continuous_sys.D)
        # Discretization of the system
        self.discretize_sys = self.continuous_sys.to_discrete(self.ts)

    def update_Li_model_propo(self, c_prop: float):
        """Update Norpineprhine Li PK model thanks to the concentration of propofol.

        Update the cl1 parameter.

        Parameters
        ----------
        c_prop : float
            Plasmatique concentration of propofol (mg/mL).

        Returns
        -------
        None.

        """
        prop_effect = np.exp(self._prop_coeff*(c_prop - self._c_prop_base))

        Anew = copy.deepcopy(self.A_init)

        cl1 = (- Anew[0, 0]*60 - self._k12)*self.v1
        cl1_prop = cl1 * prop_effect
        Anew[0, 0] = -(cl1_prop/self.v1 + self._k12)/60

        # Continuous system with blood concentration as output
        self.continuous_sys = StateSpace(Anew, self.continuous_sys.B, self.continuous_sys.C, self.continuous_sys.D)
        # Discretization of the system
        self.discretize_sys = self.continuous_sys.to_discrete(self.ts)

    def get_system_gain(self):
        """
        Compute the steady-state (DC) gain of the compartment model.

        The steady-state gain is the ratio of the output to the input when the system
        reaches equilibrium. For a stable LTI system,
        this is given by:

        .. math::
            G_{ss} = C (-A)^{-1} B + D

        where ( A, B, C, D ) are the state-space matrices.

        Returns
        -------
        float
            The scalar steady-state gain of the system (assumes SISO or extracts [0,0] for MIMO).
        """

        return (self.continuous_sys.C @ np.linalg.inv(-self.continuous_sys.A) @ self.continuous_sys.B + self.continuous_sys.D)[0, 0]


class AtracuriumModel:
    """AtracuriumModel class modelize the linear part of the PK-PD model of atracurium drug. Simulate the drug distribution in the body.

    The model is a LTI model with the form:

    .. math::  x(k+1)= Ax(k) + Bu(k)
    .. math::  y(k) = Cx(k)

    The state vector is the concentration of the drug in each compartement.

    Parameters
    ----------
    Patient_characteristic: list
        Patient_characteristic = [age (yr), height(cm), weight(kg), sex(0: female, 1: male)]
    model : str, optional
        "WardWeatherleyLago"[Ward1983,Weatherley1983,Lago1998]_.
        The default is "WardWeatherleyLago".
    model_params : dict, optional
        For "WardWeatherleyLago":

        - **'V1'**: Volume of the central compartment (ml/kg)
        - **'V2'**: Volume of the peripheral compartment (ml/kg)
        - **'Cl'**: Clearance (ml/min/kg)
        - **'t12_alpha'**: First half live time (min)
        - **'t12_beta'**: Second half live time (min)
        - **'ke0'**: Transfer rate of the first effect-site compartment (1/min)
        - **'tau'**: Time constant of the second effect-site compartment (min)

        If it is not provided average values are used.
    ts : float, optional
        Sampling time, in s. The default is 1.
    x0 : np.ndarray, optional
        Initial conditions of the model. The default is np.zeros((len(A), 1)).


    Attributes
    ----------
    ts : float
        Sampling time, in s.
    continuous_sys : control.StateSpace
        Continuous state space model.
    discrete_sys : control.StateSpace
        Discrete state space model.
    x : np.ndarray
        State vector.
    y : np.ndarray
        Output vector (hypnotic effect site concentration).

    References
    ----------
    .. [Ward1983] S. Ward et al., "Pharmacokinetics of Atracurium Besylate in Healty Patients (after a single i.v. bolus dose),"
            British Journal of Anesthesia, vol. 55, no. 2, pp. 113-116, Feb. 1983, doi: 10.1093/bja/55.2.113.
    .. [Weatherley1983] B. Weatherley et al., "Pharmacokinetics, Pharmacodynamics and Dose-Response Relationship of Atracurium Administered i.v."
            British Journal of Anesthesia, vol. 55, Suppl. 1, pp. 39S-45S, Jan. 1983.
    .. [Lago1998] P. Lago et al., "On-Line Autocalibration of a PID Controller of Neuromuscular Blockade"
            Proceedings of the 1998 IEEE International Conference on Control Applications (Cat. No.98CH36104), Trieste, Italy, Vol. 1, pp. 363-367, Sept. 1998, doi: 10.1109/CCA.1998.728448.
    """

    def __init__(self, Patient_characteristic: list,
                 model: str = None,
                 model_params: dict = None,
                 ts: float = 1,
                 x0: np.ndarray = None):
        """Init the class."""
        if model_params is None:
            model_params = {}
        self.ts = ts
        weight = Patient_characteristic[2]
        self.model = model
        if self.model is None:
            self.model = 'WardWeatherleyLago'

        if self.model == 'WardWeatherleyLago':

            # Volume of the central compartment [ml/kg]
            V1 = model_params.get('V1', 49.0)
            # Volume of the peripheral compartment [ml/kg]
            V2 = model_params.get('V2', 157.0)
            # Clearance [ml/min/kg]
            Cl = model_params.get('Cl', 5.5)
            # First half live time [min]
            t12_alpha = model_params.get('t12_alpha', 2.06)
            # Second half live time [min]
            t12_beta = model_params.get('t12_beta', 19.9)
            # Transfer rate of the first effect-site compartment [1/min]
            ke0 = model_params.get('ke0', 0.1)
            # Time constant of the second effect-site compartment [min]
            tau = model_params.get('tau', 6.2670)

            # Elimination rate constant [1/min]
            k10 = Cl/V1
            # alpha [1/min]
            alpha = math.log(2)/t12_alpha
            # beta [1/min]
            beta = math.log(2)/t12_beta
            # Transfer rate 2->1 [1/min]
            k21 = (alpha*beta)/k10
            # Transfer rate 1->2 [1/min]
            k12 = alpha + beta - k10 - k21

            # Matrices system definition
            A = np.array([[-(k10+k12),     (k21*V2)/V1,    0,      0],
                          [(k12*V1)/V2,    -k21,           0,      0],
                          [ke0,             0,            -ke0,    0],
                          [0,               0,            1/tau,  -1/tau]])/60  # 1/s
            # Conversion from [ug/s] to [ug/ml/s]
            B = np.transpose(np.array([[1/(weight*V1), 0, 0, 0]]))
            C = np.array([[0, 0, 0, 1]])
            D = np.array([[0]])

        # Continuous system
        self.continuous_sys = StateSpace(A, B, C, D)
        # Discretization of the system
        self.discretize_sys = self.continuous_sys.to_discrete(self.ts)

        # init output
        if x0 is None:
            x0 = np.zeros((len(A), 1))
        self.x = x0
        self.y = np.dot(C, self.x)

    def one_step(self, u: float) -> list:
        """Simulate one step of the model.

        .. math:: x^+ = Ax + Bu
        .. math:: y = Cx

        Parameters
        ----------
        u : float
            Infusion rate (µg/s).

        Returns
        -------
        numpy array
            Actual effect site concentration (µg/mL).

        """

        self.x = self.discretize_sys.A @ self.x + self.discretize_sys.B * u
        self.y = self.discretize_sys.C @ self.x + self.discretize_sys.D * u

        return self.y[0, 0]

    def full_sim(self, u: np.ndarray, x0: Optional[np.ndarray] = None, interp=False) -> list:
        """ Simulate the model with a given input.

        Parameters
        ----------
        u : list
            Infusion rate [mg/s].
        x0 : numpy array, optional
            Initial state. The default is None.
        interp : bool, optional
            Whether to use zero-order-hold (False, the default) or linear (True) interpolation for the input array.

        Returns
        -------
        numpy array
            List of the states value during the simulation.

        """

        if x0 is None:
            x0 = np.zeros(len(self.continuous_sys.A))

        t = np.ones_like(u)*self.ts
        t[0] = 0
        t = np.cumsum(t)

        _, _, x_lsim = lsim(
            self.continuous_sys,
            T=t,
            U=u,
            X0=x0,
            interp=interp
        )

        x = x_lsim.T
        return x

    def get_system_gain(self):
        """
        Compute the steady-state (DC) gain of the atracurium model.

        The steady-state gain is the ratio of the output to the input when the system
        reaches equilibrium. For a stable LTI system,
        this is given by:

        .. math::
            G_{ss} = C (-A)^{-1} B + D

        where ( A, B, C, D ) are the state-space matrices.

        Returns
        -------
        float
            The scalar steady-state gain of the system (assumes SISO or extracts [0,0] for MIMO).
        """

        return (self.continuous_sys.C @ np.linalg.inv(-self.continuous_sys.A) @ self.continuous_sys.B + self.continuous_sys.D)[0, 0]

    def initialize_state(self, x0: np.ndarray):
        """ Initialize the state vector

        Parameters
        ----------
        x0 : numpy array
            Initial state vector.

        """

        self.x = x0.reshape(-1, 1)
