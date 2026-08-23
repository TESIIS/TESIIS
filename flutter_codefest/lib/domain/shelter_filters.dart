/// The filter keys the UI exposes.
///
/// Matching itself happens server-side now — the chips send these keys in
/// the `disasters`/`spaces` group params (OR within a group, AND across the
/// two), and the server applies them before returning clusters or search
/// pages. This file only defines the vocabulary the chip bar and the view
/// model share.
const disasterFilterTypes = [
  'landslide',
  'tsunami',
  'earthquake',
  'flood',
  'nuclear',
];

/// The space-type filter keys the UI exposes.
const spaceFilterTypes = ['indoor', 'outdoor'];
