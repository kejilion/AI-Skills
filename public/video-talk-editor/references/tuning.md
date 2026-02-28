# Tuning Guide

## Silence Detection

| Environment | Threshold (dB) | Min Duration (s) |
|---|---|---|
| Studio / quiet room | -40 | 0.5 |
| Home recording | -35 | 0.6 |
| Noisy / outdoor | -28 | 0.8 |

`--padding`: extra seconds kept before/after speech (default 0.12s).
Increase to 0.2 for natural breathing room; decrease to 0.05 for aggressive cuts.

## Filler Words

### Chinese
嗯, 啊, 呃, 那个, 就是, 就是说, 然后, 对吧, 其实, 反正, 怎么说呢, 这个

### English
um, uh, like, you know, basically, actually, so, right, I mean, kind of, sort of

### Japanese
えーと, あの, その, まあ, なんか, ちょっと

## Crossfade

| Style | Duration (s) | Notes |
|---|---|---|
| Jump cut (YouTube) | 0 | Hard cuts, energetic feel |
| Subtle | 0.03-0.05 | Removes click artifacts |
| Smooth | 0.08-0.15 | Natural, professional |
| Soft | 0.2-0.3 | Cinematic, slow-paced |

## Subtitle Styles

### Clean white (default)
```
FontSize=22,FontName=Noto Sans CJK SC,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2,Shadow=1
```

### Bold yellow (tutorial)
```
FontSize=26,FontName=Noto Sans CJK SC,PrimaryColour=&H0000FFFF,OutlineColour=&H00000000,Outline=3,Shadow=2
```

### Minimal bottom
```
FontSize=18,FontName=Noto Sans CJK SC,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,Outline=1,Shadow=0,MarginV=30
```
