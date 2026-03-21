# SPDX-License-Identifier: PMPL-1.0-or-later
# Example R analysis script for julianiser translation demo.
#
# This script demonstrates common dplyr/ggplot2 patterns that julianiser
# can detect and translate into Julia equivalents.

library(dplyr)
library(ggplot2)

# Load and filter data.
data <- read_csv("experiment_results.csv")
clean_data <- filter(data, !is.na(value))

# dplyr pipeline: group, summarise, arrange.
summary_stats <- clean_data %>%
  group_by(treatment) %>%
  summarise(
    mean_value = mean(value),
    sd_value = sd(value),
    n = n()
  ) %>%
  arrange(desc(mean_value))

# Join with metadata.
metadata <- read_csv("metadata.csv")
enriched <- left_join(summary_stats, metadata, by = "treatment")

# Statistical test.
model <- lm(value ~ treatment + age + gender, data = clean_data)

# Visualisation.
p <- ggplot(clean_data, aes(x = treatment, y = value, fill = treatment)) +
  geom_bar(stat = "summary", fun = "mean") +
  geom_point(position = position_jitter(width = 0.2), alpha = 0.5) +
  theme(legend.position = "none")

write_csv(enriched, "enriched_results.csv")
print(summary_stats)
