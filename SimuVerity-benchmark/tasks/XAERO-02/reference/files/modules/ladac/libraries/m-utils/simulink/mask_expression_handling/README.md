# Mask Expression Handling
Mask Expression Handling provides a solution for a special Simulink problem. In the following sections, the [problem](#the-problem) is explained in detail and our [solution](#the-solution) to this problem is presented.



## The problem

### TL;DR
You are trying to generate code for a Simulink model and **all** of the following things are true:
- The exported code should contain tunable parameters
- The model contains blocks with masks and the masks have parameters of type 'Edit'
- You are using expressions with variables as input to your mask parameter fields
- The parameters are of data type `single` (See also: [Floating-Point Numbers](https://mathworks.com/help/matlab/matlab_prog/floating-point-numbers.html))

In this case, you will get a [loss of tunability](https://mathworks.com/help/simulink/gui/detect-loss-of-tunability.html) error during code generation, because Simulink can't handle expressions with variables of data type `single` in masks. Our solution enables code generation for this special scenario. However, it must be said that the [tunable expression limitations](https://mathworks.com/help/rtw/ug/limitations-for-block-parameter-tunability-in-the-generated-code.html) must still be taken into account.


### In detail
Let's assume we have a Simulink block with a mask.

![mask-with-expression](https://github.com/iff-gsc/m-Utils/assets/27336815/80f31a44-749a-4f0a-931b-0071c2de149d)

If the [model](./maskExprHandling_example/maskExprHandling_example.slx) containing this block is configured so that `param.a` and `param.b` are tunable and these parameters are of data type `double` (the default datatype in MATLAB/Simulink), code generation for this model will work as expected. However, if `param.a` and `param.b` are of data type `single`, the code generation does not work and gives the following error message.

![loss-of-tunability-error-message](https://github.com/iff-gsc/m-Utils/assets/27336815/ea6858df-6ac5-4b6d-a6dc-3bf6b05c3810)

We could set "Detect loss of tunability" to "warning" instead of "error" in the model configuration and still generate code for this model, but the generated code would insert the numeric value of this expression (as specified in the error message) and this part of the model would not be tunable.

We also contacted the MathWorks support about this limitation, who confirmed that this limitation exists, but offered a [different solution](#another-workaround) to this problem.



## The solution
Our solution to this problem is an additional configuration section in the mask, that allows to switch behaviour between "default" and "passthrough (tunable)". If set to "passthrough", every mask parameter containing an expression with a variable is written directly into the subblocks using the mask parameter. At the same time the parameter becomes disabled in the mask and can only be changed again if set back to "default". This solution reverses the abstraction of the mask to a certain extent, but makes it possible to switch back and forth. Nested masks are also supported, but require this method to be implemented in each mask. Below you can see the same Simulink block with a mask, but this time with mask expression handling implemented.

![mask-with-expression-and-mask-expression-handling-default](https://github.com/iff-gsc/m-Utils/assets/27336815/bdfc4182-5ed3-4723-bb32-319ca4ad4fe7)

If set to "passthrough", the mask parameter is deactivated and can only be changed again after switching back to "default".

![mask-with-expression-and-mask-expression-handling-passthrough](https://github.com/iff-gsc/m-Utils/assets/27336815/38668cb5-0d26-4fc7-af4c-56954e5b5a9b)

Now the tunable code generation succeeds, even if `param.a` and `param.b` are of data type `single`.



## How to use it
Mask expression handling requires an additional configuration section and a function call to [`maskExprHandling()`](./maskExprHandling.m) in the "Initialization commands" of the mask. Please have a look at the provided [example model](./maskExprHandling_example/maskExprHandling_example.slx) to better understand the required changes.

We provide a function that adds mask expression handling automatically to a block with a mask. The function is called [`maskExprHandlingAdd2Block()`](./maskExprHandlingAdd2Block.m) and requires a path or a handle to the block as an argument. You can open a model, click on the block you want to change and execute `maskExprHandlingAdd2Block(gcb)`. The function also checks for nested masks and supports the iterative modification of all subblocks with a mask. It has some built-in checks and should work in many cases.



## Restrictions
This solution works only for scalar parameters in expressions and has not been tested for other cases. If you try to use it for multidimensional parameters (e.g. arrays or matrices), errors will occur.


## Another Workaround
We contacted the MathWorks support in November 2023 to get more information about this issue. A possible workaround is to use [referenced models with a model mask](https://mathworks.com/help/simulink/ug/create-and-reference-a-masked-model.html). This does indeed support expressions with variables of data type `single`, however we have noticed that each referenced model is exported as separate class in the exported code. Even though this behaviour can possibly be changed via the settings, we have not investigated this solution further.
