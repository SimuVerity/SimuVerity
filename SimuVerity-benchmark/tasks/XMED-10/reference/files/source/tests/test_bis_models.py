from python_anesthesia_simulator.pd_models import BIS_model
import numpy as np
# BIS_model object to test the Bouillon propofol-remifentanil interaction model
bouillon_bis_model = BIS_model('Bouillon')

# BIS_model object to test the Vanluchene propofol model
vanluchene_bis_model = BIS_model('Vanluchene')

# BIS_model object to test the Eleveld propofol model
eleveld_bis_model = BIS_model('Eleveld', age=70)

# BIS_model object to test the Fuentes propofol-remifentanil interaction model
fuentes_bis_model = BIS_model('Fuentes')

# BIS_model object to test the Yumuk propofol-remifentanil model
yumuk_bis_model = BIS_model('Yumuk')

list_of_model = [
    bouillon_bis_model,
    vanluchene_bis_model,
    eleveld_bis_model,
    fuentes_bis_model,
    yumuk_bis_model,
]
propo_model = [
    vanluchene_bis_model,
    eleveld_bis_model,
]
interaction_model = [
    bouillon_bis_model,
    fuentes_bis_model,
    yumuk_bis_model,
]

# Create a BIS_model object initialized with custom parameters equal to those of bouillon
custom_bis_model_bouillon = BIS_model(hill_param = [4.47, 19.3, 1.43, 0, 97.4, 97.4, 0])

# Create a BIS_model object initialized with custom parameters equal to those of vanluchene
custom_bis_model_vanluchene = BIS_model(hill_param = [4.92, 0, 2.69, 0, 95.9, 87.5, 0])


# tests
def test_default_initialization():
    """Ensure that the default models give correct results"""
    # Check results at low concentrations
    for model in list_of_model:
        assert model.compute_bis(0, 0) >= 90

    # Check results at high concentrations
    for model in propo_model:
        assert model.compute_bis(16) <= 20
    for model in interaction_model:
        assert model.compute_bis(12, 8) <= 20
    # Check results at clinically recommended concentrations
    assert vanluchene_bis_model.compute_bis(5) <= 60
    assert vanluchene_bis_model.compute_bis(5) >= 40
    assert eleveld_bis_model.compute_bis(2.5) <= 60
    assert eleveld_bis_model.compute_bis(2.5) >= 40
    assert bouillon_bis_model.compute_bis(3, 6) <= 60
    assert bouillon_bis_model.compute_bis(3, 6) >= 40
    assert fuentes_bis_model.compute_bis(3, 6) <= 60
    assert fuentes_bis_model.compute_bis(3, 6) >= 40
    assert yumuk_bis_model.compute_bis(4, 8) <= 60
    assert yumuk_bis_model.compute_bis(4, 8) >= 40


def test_custom_initialization():
    """Ensure that the custom models give correct results by comparing with 
    the results given by the default models"""
    # Check results at low concentrations
    assert abs(vanluchene_bis_model.compute_bis(0) -
               custom_bis_model_vanluchene.compute_bis(0)) < 1e-3
    assert abs(bouillon_bis_model.compute_bis(0, 0) -
               custom_bis_model_bouillon.compute_bis(0, 0)) < 1e-3
    # Check results at high concentrations
    assert abs(vanluchene_bis_model.compute_bis(16) -
               custom_bis_model_vanluchene.compute_bis(16)) < 1e-3
    assert abs(bouillon_bis_model.compute_bis(12, 8) -
               custom_bis_model_bouillon.compute_bis(12, 8)) < 1e-3
    # Check results at clinically recommended concentrations
    assert abs(vanluchene_bis_model.compute_bis(5) -
               custom_bis_model_vanluchene.compute_bis(5)) < 1e-3
    assert abs(bouillon_bis_model.compute_bis(3, 6) -
               custom_bis_model_bouillon.compute_bis(3, 6)) < 1e-3


def test_inverse_hill():
    """Check that the inversion of the hill function is giving correct results"""
    # Check results at low concentrations
    for model in propo_model:
        assert abs(model.inverse_hill
                   (model.compute_bis(0)) - 0) < 1e-3
        assert abs(model.inverse_hill
                   (model.compute_bis(16)) - 16) < 1e-3
        assert abs(model.inverse_hill
                   (model.compute_bis(4)) - 4) < 1e-3

    for model in interaction_model:
        assert abs(model.inverse_hill
                   (model.compute_bis(0, 0), 0) - 0) < 1e-3
        assert abs(model.inverse_hill
                   (model.compute_bis(12, 8), 8) - 12) < 1e-3
        assert abs(model.inverse_hill
                   (model.compute_bis(3, 6), 6) - 3) < 1e-3


def test_vectorized_input():
    for model in propo_model:
        assert model.compute_bis(np.array([0, 20]))[0] > 90
        assert model.compute_bis(np.array([0, 20]))[1] < 20
    for model in interaction_model:
        assert model.compute_bis(np.array([0, 12]), np.array([0, 8]))[0] > 90
        assert model.compute_bis(np.array([0, 12]), np.array([0, 8]))[1] < 20


if __name__ == '__main__':
    # bouillon_bis_model.plot_surface()
    # vanluchene_bis_model.plot_surface()
    # eleveld_bis_model.plot_surface()
    # fuentes_bis_model.plot_surface()
    # kern_bis_model.plot_surface()
    # mertens_bis_model.plot_surface()
    # yumuk_bis_model.plot_surface()

    # test
    test_default_initialization()
    test_custom_initialization()
    test_inverse_hill()
    test_vectorized_input()
    print("All test passed successfully!")
