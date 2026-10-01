Introduction
============


Installation
------------

Set your terminal path to the PAS package and install it using pip:

.. code-block:: console

   $ pip install .

Overview of the Simulator Features
-----------------------------------

The proposed simulator is a modular, extensible platform for evaluating anesthesia controllers.  
It accepts as inputs infusion rates for propofol, remifentanil, norepinephrine, and atracurium.  
It provides as outputs a comprehensive set of clinical variables including Bispectral Index (BIS), tolerance to laryngoscopy (TOL), loss of consciousness (LOC), mean arterial pressure (MAP), cardiac output (CO), total peripheral resistance (TPR), stroke volume (SV), heart rate (HR) and train-of-four (TOF).  
Designed for physiological fidelity and user customizability, its core features are summarized below.

* **Flexible pharmacokinetic/pharmacodynamic (PK/PD) modeling**  
  A portfolio of well-established PK/PD models is provided, acknowledging that no single model is universally optimal.  
  This multi-model approach enhances the simulator's generalizability across different patient populations. See sections :ref:`pharmacokinetics` and :ref:`pharmacodynamics` for more details.

* **Mechanism-based hemodynamic modelling**  
  Hemodynamic effects are simulated using a state-of-the-art mechanism-based model [Su2023]_ to provide a realistic representation of safety-critical hemodynamic variables.  A Physiologically coherent method for simulating norepinephrine effect is also included. See section :ref:`hemodynamics` for more details.

* **Variability representation**  
  The simulator incorporates both intra- and inter-patient variability.  
  Users can perturb PK/PD parameters according to statistical distributions available in the literature.  
  They can also define custom virtual cohorts by selecting physical characteristics and PD parameters. See example PID_example_ for more details.


* **Realistic monitor behavior**  
  To assess controller robustness, the simulator includes a model of BIS calculation delay, dependent on the Signal Quality Index (SQI) (see :ref:`delay`), and realistic measurement noise (see :ref:`noise_identif`), mimicking artifacts from real-world clinical monitors.

* **Clinically relevant disturbances**  
  A library of surgical stimulation profiles and a novel, physiologically-grounded blood loss model are included.  
  The latter maintains dynamic links between hemodynamic variables and updates PK models. This allows hemorrhagic shock to be simulated.

* **Assessment on an open-source dataset**  
  The simulator's modeling capabilities have been assessed by means of the high-quality clinical data of 54 cases from the open-source VitalDB database [Lee2022]_, selected using clear, defined criteria. See section :ref:`disurbance_identification` for more details.

* **Data-driven customization**  
  An integrated identification tool allows users to fine-tune the hemodynamic model parameters and identify disturbance profiles (e.g., intubation, incision) using their own clinical data.  
  This enables adaptation to specific populations (e.g., pediatric, elderly) and/or to a specific type of surgery.  
  This can also be exploited to create virtual patient copies, opening avenues for the testing of personalized treatment strategies. See section :ref:`disurbance_identification` and repository `PAS_vs_VitalDB <https://github.com/AnesthesiaSimulation/PAS_vs_vitalDB>`_ for more details.

* **MATLAB/Simulink compatibility**  
  While the simulator is written in Python, we provide a seamless interface to MATLAB/Simulink via the MATLAB-Python interface.  
  This allows control systems engineers to directly use the simulator within their familiar workflow while maintaining a single codebase.  
  This favors a more sustainable long-term development, as separate Python and MATLAB implementations are difficult to maintain and upgrade. See the :ref:`matlab` section for more details truc.

* **Open-source framework**  
  The simulator is distributed as a fully open-source project on GitHub, supported by comprehensive documentation, a contributor code of conduct, and automated test suites to ensure code integrity and foster community-driven development.

* **Additional utilities**  
  Other features include a Target-Controlled Infusion (TCI) module (see TCI_simulation_, patient state initialization at a given state, clinical alarm simulation, and computation of BIS-based control performance metrics commonly employed in the literature.

.. _TCI_simulation: examples/TCI_example.ipynb
.. _PID_example: examples/Merigo_PID.ipynb

References
----------

..  [Su2023] H. Su, J. V. Koomen, D. J. Eleveld, M. M. R. F. Struys, and P. J. Colin, “Pharmacodynamic
    mechanism-based interaction model for the haemodynamic effects of remifentanil and propofol in healthy
    volunteers,” British Journal of Anaesthesia, vol. 131, no. 2, pp. 222–233, Aug. 2023,
    doi: https://10.1016/j.bja.2023.04.043.

..  [Lee2022] H.-C. Lee, Y. Park, S. B. Yoon, S. M. Yang, D. Park, and C.-W. Jung, “VitalDB, a high-fidelity
    multi-parameter vital signs database in surgical patients,” Sci Data, vol. 9, no. 1, p. 279,
    Jun. 2022, doi: https://10.1038/s41597-022-01411-5.
