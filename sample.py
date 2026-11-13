import pandas as pd

chunks = pd.read_csv("2019-Oct.csv", chunksize=1_000_000)
out = []
for c in chunks:
    out.append(c[c["user_id"] % 100 == 0])

df = pd.concat(out)
df.to_csv("events_sample.csv", index=False)
print(len(df))