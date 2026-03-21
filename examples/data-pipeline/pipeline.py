# SPDX-License-Identifier: PMPL-1.0-or-later
# Example Python data pipeline for julianiser translation demo.
#
# This script demonstrates common pandas/numpy patterns that julianiser
# can detect and translate into Julia equivalents.

import pandas as pd
import numpy as np

# Load data from CSV.
df = pd.read_csv("sales_data.csv")

# Filter rows and compute derived columns.
filtered = df.dropna()
filtered["total"] = filtered["quantity"] * filtered["price"]

# Group and aggregate.
summary = filtered.groupby("category").agg({"total": "sum", "quantity": "mean"})

# Numerical computation with numpy.
prices = np.array(filtered["price"].values)
quantities = np.array(filtered["quantity"].values)
weighted_avg = np.mean(prices * quantities) / np.mean(quantities)

# Statistical summary.
std_dev = np.std(prices)
correlation = np.dot(prices - np.mean(prices), quantities - np.mean(quantities))

# Sort and output.
result = summary.sort_values("total", ascending=False)
result.to_csv("output.csv")

print(f"Weighted average price: {weighted_avg:.2f}")
print(f"Price std dev: {std_dev:.2f}")
print(f"Price-quantity correlation: {correlation:.4f}")
