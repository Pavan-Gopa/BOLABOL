export interface MandalaSettings {
  // Grid settings
  sections: number;
  rings: number;
  showGridLines: boolean;
  showRings: boolean;
  reflect: boolean; // Dihedral symmetry

  // Rose Curve (Petals)
  petalLength: number; // a
  petalFrequency: number; // k
  showPetals: boolean;

  // Spiral
  spiralGrowth: number; // b
  showSpiral: boolean;
}

export type AppMode = 'TEMPLATE' | 'WORKSPACE';

export interface Point {
  x: number;
  y: number;
}

export interface Stroke {
  points: Point[];
  color: string;
  size: number;
  type: 'brush' | 'dots';
  sections: number; // Captured at time of creation
}
