Non-linear interactions 
=========================
Cardiac output dependency
--------------------------
Several studies have shown the influence of cardiac output (CO) on the pharmacokinetics of propofol ([Adachi2001]_, [Kurita2002]_, [Upton1999]_). In [Bienert2020]_, the authors proposed the assumption that the clearance rate of propofol and fentanil could be proportional to CO resulting in a non-constant clearance rate. In the simulator, the same assumption is made for propofol and extended to remifentanil and norepinephrine clearance rates in the PK model. 

.. math::
    Cl(t) = Cl_0 \frac{CO(t)}{CO_0}

Where :math:`Cl` denotes all the clearances rates of each drugs and each compartment, and :math:`Cl_0` and :math:`CO_0` the initial clearance rates and cardiac output.

This behavior can be activated or deactivated (default) to simulate the interaction between CO and the PK systems.

Blood loss modelling
----------------------
When important, blood loss can be considered as a shock situation for the patient. It strongly affect the haemodynamic system and also all the inner working of multiple organs in the body. Regarding anesthesia modelling, blood loss is known to change the distribution of drugs in the body ([Johnson2001]_, [Johnson2003]_, [Kurita2009]_). In fact, the reduced volume of blood will affect the PK system of the drugs. Thus, during a blood loss simulation the blood volume (first compartment volume) is updated in all the PK models. For this, we consider the volume of the first compartment of propofol as the "true" volume of blood in the patient body and update the other PK model according to the fraction of the remaining blood volume over the initial blood volume.

In addition to the effect of blood loss in the PK models, the crude assumption that SV is proportional to the blood volume is made in the simulator. The transient behavior of bleeding and transfusion does not verify this assumption, however the steady-state experimental values do agree with it [Rinehart2011]_. Thus, in case of bleeding a term is added to the dynamic equations of SV such that it converge to the wanted value. The equations are the following:

.. math::
    SV_{wanted}(t) = SV_{no\_bleeding}(t) \frac{V_{1,p}(t)}{V_{1,p}(0)}

where :math:`SV_{no\_bleeding}(t)` is the stroke volume computed without considering bleeding, and :math:`V_{1,p}(t)` is the volume of the first compartment of propofol PK model at time :math:`t`. The dynamic of SV in the system including the effect of bleeding is then given by:

.. math::
    \begin{align}
    \dot{SV}^*(t) &=  \frac{k_{in\_SV}}{RMAP(t)^{FB}}(1 + EFF_{prop\_SV}(t)) \\
    & - k_{out} SV^*(t) (1 - EFF_{remi\_SV}(t)) \\
    & \textcolor{blue}{ + k_{bleeding}(SV_{wanted}(t)- SV(t))}
    \end{align}

A more complex hemodynamic model should be integrated to obtain better results. The simulator also takes into account the fact that the BIS pharmacodynamics depends on bleeding [Kurita2009]_ leading to a deeper hypnosis state, and these dependencies have been chosen to match the experimental results of the study.

In case of bleeding, considering :math:`\rho = \frac{V_{1,p}(t)}{V_{1,p}(0)}` with :math:`V_{1,p}(0)` the initial first compartment volume of propofol PK model and :math:`V_{1,p}(t)` the volume updated thanks to the rates of blood loss given by the user, the equations are the following:

.. math:: 
    \begin{align}
    V_1(t) &= \rho V_1(0) \\
    C_{50p,BIS}(t) &= C_{50p,BIS}(0) - 6(1-\rho)
    \end{align}


where :math:`V_1(t)` is the volume of the first compartment of all drug PK model and :math:`C_{50p,BIS}(t)` the half effect concentration of propofol on BIS. 

Note that with this modelling approach, because the PK model is affected both by the loss of blood volume and reduction of cardiac output, the time constant of the system are not importantly affected. However, as the blood volume is reduced and the patient sensitivity to propofol increase, the BIS will decrease quickly if the rates of propofol is not updated.

References
----------

.. [Adachi2001] Adachi, Y. U., Watanabe, K., Higuchi, H., & Satoh, T. (2001).
    The Determinants of Propofol Induction of Anesthesia Dose. Anesthesia & Analgesia,
    92(3), 656. https: //doi.org/10.1213/00000539-200103000-00020
.. [Kurita2002] Kurita, T., Takata, K., Morita, K., Morishima, Y., Uraoka, M., Katoh, T., & Sato, S. (2009).
    The Influence of Hemorrhagic Shock on the Electroencephalographic and Immobilizing
    Effects of Propofol in a Swine Model. Anesthesia & Analgesia, 109(2), 398–404.
    https: //doi.org/10.1213/ane.0b013e3181a96f9a
.. [Upton1999] Upton, R. N., Ludbrook, G. L., Grant, C., & Martinez, A. M. (1999).
    Cardiac Output is a Determinant of the Initial Concentrations of Propofol After
    Short-Infusion Administration. Anesthesia & Analgesia, 89(3), 545.
    https://doi.org/10.1213/00000539-199909000-00002
.. [Bienert2020] Bienert, A., Sobczyński, P., Młodawska, K., Hartmann-Sobczyńska,
    R., Grześkowiak, E., & Wiczling, P. (2020). The influence of cardiac output
    on propofol and fentanyl pharmacokinetics and pharmacodynamics in patients
    undergoing abdominal aortic surgery. Journal of Pharmacokinetics and Pharmacodynamics,
    47 (6), 583–596. https://doi.org/10.1007/ s10928-020-09712-1
.. [Johnson2001] Johnson, K. B., Kern, S. E., Hamber, E. A., McJames, S. W., Kohnstamm,
    K. M., & Egan, T. D. (2001). Influence of Hemorrhagic Shock on Remifentanil:
    A Pharmacokinetic and Pharmacodynamic Analysis. Anesthesiology, 94(2), 322–332.
    https://doi.org/10.1097/ 00000542-200102000-00023
.. [Johnson2003] Johnson, K. B., Egan, T. D., Kern, S. E., White, J. L., McJames, S. W., Syroid,
    N., Whiddon, D., & Church, T. (2003). The Influence of Hemorrhagic Shock on Propofol:
    A Pharmacokinetic and Pharmacodynamic Analysis. Anesthesiology, 99(2), 409–420.
    https://doi.org/10.1097/00000542-200308000-00023
.. [Kurita2009] Kurita, T., Takata, K., Morita, K., Morishima, Y., Uraoka, M., Katoh,
    T., & Sato, S. (2009). The Influence of Hemorrhagic Shock on the
    Electroencephalographic and Immobilizing Effects of Propofol in a Swine Model.
    Anesthesia & Analgesia, 109(2), 398–404. https: //doi.org/10.1213/ane.0b013e3181a96f9a
.. [Rinehart2011] Rinehart, J., Alexander, B., Manach, Y. L., Hofer, C. K., Tavernier,
    B., Kain, Z. N., & Cannesson, M. (2011). Critical Care, 15(6), R278. https://doi.org/10.1186/cc10562
