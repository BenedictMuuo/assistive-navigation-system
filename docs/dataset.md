# Dataset

How the training images were obtained, and from where.

---

## Summary

| | |
|---|---|
| Total images | 3,200 |
| Classes | 8 |
| Images per class | 400 |
| Split per class | 280 train / 60 validation / 60 test |
| Image size | 224 × 224 RGB, JPEG |
| Built on | 15 September 2026 |

The images are not stored in this repository. `model/build_dataset.py`
rebuilds them from public sources in about an hour, so the script is version
controlled and the 39 MB of images is not.

---

## Sources

| Source | Classes it provided | Images used |
|--------|--------------------|-------------|
| Open Images V7 | chair, table, door, bag, person, stairs | 2,400 |
| HomeObjects-3K | chair, table, door | topped up the above |
| ADE20K | wall, background | 800 |

**Open Images V7** — Google's public dataset of 601 object classes. Each class
was downloaded separately so that rarer objects received their own quota. In a
single shared batch, chairs and people filled up while bags and stairs came
back nearly empty.

The `bag` class collects handbags, backpacks, suitcases and briefcases
together. All four are the same obstacle to a visually impaired user and
warrant the same warning. The `table` class likewise includes desks, coffee
tables and dining tables.

**HomeObjects-3K** — about 3,000 indoor photographs across 12 household
classes, in varied lighting and orientation. Used to add chair, table and door
images that look like ordinary rooms rather than catalogue photography.

**ADE20K** — a scene-parsing dataset in which every pixel carries a label.
Rather than looking for boxed objects, the script cuts square patches from
regions labelled wall and regions labelled floor. Floor patches form the
`background` class, meaning a clear path with nothing in the way.

No public dataset provides `wall` or `background` as boxed objects, because
neither is an object. Pixel-level labelling is what makes them available.

---

## From detection data to classification data

Open Images and HomeObjects-3K are object *detection* datasets: each image has
boxes drawn around the objects in it. This project trains an image
*classifier*, which needs one label for a whole image.

The build script crops each box into its own image and files it in the folder
named after its class. A box labelled chair becomes a chair image. Each crop
keeps 10% padding around the box so the object has some surrounding context.
Boxes smaller than 80 pixels are discarded, as they blur badly when resized to
224 × 224.

---

## Balancing and splitting

**Duplicate removal.** Every crop is hashed, and repeats are dropped. The
public sources overlap more than expected.

**Even draw across sources.** Each class is filled by taking from every
available source in turn, so no single source dominates a class. A class fed
by one source learns that source's photographic style rather than the object
itself.

**Splitting by source photograph.** One photograph can produce many crops — a
classroom shot yields ten chairs. All crops from one photograph go into the
same split. If some went to training and others to testing, the model would be
tested on photographs it had already learned from, and the accuracy figure
would be meaningless.

Because photographs yield different numbers of crops, the split is not made at
random. Larger photographs are placed first, each into whichever split is
furthest below its target for the classes in that photograph. The result is an
exact 70/15/15 split for every class.

---

## Licences

| Source | Licence |
|--------|---------|
| Open Images V7 | Images Creative Commons (from Flickr); annotations CC BY 4.0 by Google |
| HomeObjects-3K | Published by Ultralytics; check the dataset page for current terms |
| ADE20K | MIT CSAIL; free for research use |

All three permit academic use. The exact terms should be confirmed on each
dataset page before submission and cited in the references.

---

## Known weaknesses

**No Kenyan images.** The whole dataset is international. Nothing in it was
photographed in the environment where the system will be demonstrated.

**Crops, not scenes.** Training images are tightly framed single objects. The
phone camera sees whole rooms.

**Wall and background come from scene photographs**, cut from labelled regions,
not captured from the chest height and angle a user's phone would have.

---

## Planned additions

100–150 locally photographed images per class, collected around Strathmore
University, covering:

- varied angles: front, side, low, high
- varied distances: near, medium, far
- varied light: bright daylight, evening, indoor lighting
- partly blocked views

The build script picks these up automatically from `local/<class>/` folders and
merges them with the public images.

For photographs containing people, verbal consent is obtained and recorded.
Images showing faces are avoided where possible — a person's back or side works
equally well for training.

---

## Rebuilding

```bash
python model/build_dataset.py --sources openimages,homeobjects,ade20k --cap 400
```

| Option | Effect |
|--------|--------|
| `--cap N` | Images per class. Default 400. |
| `--sources` | Which sources to draw from, comma separated. |
| `--quality N` | JPEG quality, 60–95. Lower gives a smaller output. |

The script writes `assistive_dataset.zip` along with `manifest.csv`, which
records the source of every single image.
