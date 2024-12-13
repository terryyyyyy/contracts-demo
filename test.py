from sympy import symbols, Eq, solve
from scipy.integrate import quad
import numpy as np
import matplotlib.pyplot as plt

# 定义变量
a, b, x = symbols('a b x', real=True)

# 定义方程 y = a - b / (x + 5 * 10^26)
y = a * (x + 3 * 10 ** 25) ** 2 + b

# 条件 1：x = 0 时，y = 1.5e9
condition1 = Eq(y.subs(x, 0), 1_800_000_000)

# 条件 2：x = 7e26 时，y = 2e10
condition2 = Eq(y.subs(x, 7 * 10**26), 24_000_000_000)

# 解方程组
solutions = solve([condition1, condition2], (a, b))

print(solutions)
a = solutions[a]
b = solutions[b]

# #  1500000000    0.000000001
# # 24000000000   0.000000015
# {a: 9/280000000000000000, b: -12000000000/7}

# Define the function y = 177000000000/7 - 33300000000000000000000000000000000000/7/(x + 2 * 10^26)y = 177000000000/7 - 33300000000000000000000000000000000000/7/(x + 2 * 10^26)
def y_function(x):
    return a * (x + 3 * 10 ** 25) ** 2 + b


# 计算 y_function 从 0 到 7 * 10^26 的积分
integral_result, error = quad(y_function, 0, 1 * 10**25)

print(f"1000万代币结果需要: {integral_result / 10**36}, 误差为: {error}")

integral_result, error = quad(y_function, 0, 2 * 10**25)

print(f"2000万代币结果需要: {integral_result / 10**36}, 误差为: {error}")

integral_result, error = quad(y_function, 0, 1 * 10**26)

print(f"1亿代币需要: {integral_result / 10**36}, 误差为: {error}")

integral_result, error = quad(y_function, 0, 7 * 10**26)

print(f"7亿代币需要: {integral_result / 10**36}, 误差为: {error}")

# Generate x values from 0 to 7e26
x_values = np.linspace(0, 7 * 10**26, 500)

# Generate y values
y_values = y_function(x_values)

# Plot the function
plt.figure(figsize=(12, 6))
plt.plot(x_values, y_values, label=r'$y = \frac{27}{980000000000000000000000000000000000000000000} \times (x + \frac{700000000000000000000000000}{3})^2$', color='b')
plt.title(r'Plot of $y = \frac{27}{980000000000000000000000000000000000000000000} \times (x + \frac{700000000000000000000000000}{3}) ^ 2$')
plt.xlabel('x')
plt.ylabel('y')
plt.grid(True)
plt.legend()
plt.show()