// Club colours, matching Theme.clubColor in the iOS app.

const COLOURS = {
  ARS: '#f01c29',
  AVL: '#6b1740',
  BOU: '#d91a21',
  BRE: '#e82629',
  BHA: '#0057b5',
  BUR: '#6b1a40',
  CHE: '#052699',
  COV: '#57b5e8',
  HUL: '#f08c21',
  CRY: '#1a4799',
  EVE: '#00338c',
  FUL: '#1a1a1f',
  IPS: '#3352a6',
  LEE: '#facc1a',
  LEI: '#0052a1',
  LIV: '#c70d21',
  MCI: '#6bbfe6',
  MUN: '#d91721',
  NEW: '#26262b',
  NFO: '#de2121',
  SOU: '#d60f24',
  SUN: '#e61a24',
  TOT: '#12174d',
  WHU: '#7d0d30',
  WOL: '#fab521',
};

export function clubColour(shortName) {
  return COLOURS[(shortName || '').toUpperCase()] || '#5a5a6b';
}
