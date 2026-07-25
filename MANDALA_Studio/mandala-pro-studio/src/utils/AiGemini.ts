import { GoogleGenAI } from '@google/genai';

export interface MoodMandalaSetup {
  segments: number;
  layers: number;
  mirror: boolean;
  showGridLines: boolean;
  showRings: boolean;
  
  petalLength: number;
  petalFrequency: number;
  showPetals: boolean;
  
  spiralGrowth: number;
  showSpiral: boolean;

  brushType: 'vector' | 'dotting' | 'glow' | 'pixel' | 'sketch' | 'rainbow';
  brushColor: string;
  brushSize: number;
  brushOpacity: number;
  
  soundscapeMood: 'cosmic' | 'forest' | 'meditation' | 'wind';
  aiExplanation: string;
}

/**
 * Gets a prompt-based mandala layout configuration from Google Gemini
 */
export async function generateMandalaFromMood(prompt: string, customApiKey?: string): Promise<MoodMandalaSetup> {
  // Try to find API key from argument, window/process environment, or localStorage
  const apiKey = customApiKey || 
                 localStorage.getItem('gemini_api_key') || 
                 (typeof process !== 'undefined' ? process.env.GEMINI_API_KEY : '') ||
                 '';

  if (!apiKey) {
    throw new Error('Missing Gemini API Key. Please add your key in the Settings tab.');
  }

  const ai = new GoogleGenAI({ apiKey });

  const systemInstruction = `You are a generative art and meditation guide for the Mandala Studio application. 
Given a user's mood description or drawing prompt, configure a geometric mandala template, a custom drawing brush, and a soundscape that represents this state.
For example:
- A stressed/anxious user should get calming cool colors (teals, blues), slow-decay soundscapes (forest or meditation), symmetrical grids (12-16 segments) to promote grounding, and the dotting tool.
- An energetic/creative user might get vibrant colors (magenta, gold), more complex segments (18-24 segments), rose curves, and the neon glow brush.
- A minimalist/focused user might get simple rings, a vector brush, and quiet wind drones.

Always return a valid JSON object matching the requested schema. Ensure the color is a hex code (e.g. "#44E2CD").`;

  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: `Generate a mandala style for this mood/request: "${prompt}"`,
      config: {
        systemInstruction,
        responseMimeType: 'application/json',
        responseSchema: {
          type: 'OBJECT',
          properties: {
            segments: { type: 'INTEGER', description: 'Number of radial segments, must be an even number between 4 and 48' },
            layers: { type: 'INTEGER', description: 'Number of concentric rings, between 2 and 15' },
            mirror: { type: 'BOOLEAN', description: 'Whether to use mirror dihedral symmetry' },
            showGridLines: { type: 'BOOLEAN', description: 'Show radial segment lines' },
            showRings: { type: 'BOOLEAN', description: 'Show concentric ring lines' },
            petalLength: { type: 'INTEGER', description: 'Rose curve petal size percentage, 0 to 100' },
            petalFrequency: { type: 'INTEGER', description: 'Rose curve petal frequency, 1 to 12' },
            showPetals: { type: 'BOOLEAN', description: 'Whether to show the rose curve guidelines' },
            spiralGrowth: { type: 'NUMBER', description: 'Spiral growth rate, 0.1 to 1.5' },
            showSpiral: { type: 'BOOLEAN', description: 'Whether to show the logarithmic spiral guidelines' },
            brushType: { 
              type: 'STRING', 
              enum: ['vector', 'dotting', 'glow', 'pixel', 'sketch', 'rainbow'],
              description: 'Brush mode to start drawing' 
            },
            brushColor: { type: 'STRING', description: 'Vibrant neon CSS hex color code representing the mood' },
            brushSize: { type: 'INTEGER', description: 'Brush width in pixels, 2 to 40' },
            brushOpacity: { type: 'INTEGER', description: 'Brush opacity percentage, 10 to 100' },
            soundscapeMood: { 
              type: 'STRING', 
              enum: ['cosmic', 'forest', 'meditation', 'wind'],
              description: 'The procedural audio synth mood to play' 
            },
            aiExplanation: { type: 'STRING', description: 'A short 2-sentence empathetic description of why this geometry, color palette, and audio drone matches their current state.' }
          },
          required: [
            'segments', 'layers', 'mirror', 'showGridLines', 'showRings', 
            'petalLength', 'petalFrequency', 'showPetals', 'spiralGrowth', 'showSpiral', 
            'brushType', 'brushColor', 'brushSize', 'brushOpacity', 'soundscapeMood', 'aiExplanation'
          ]
        }
      }
    });

    const text = response.text;
    if (!text) {
      throw new Error('Empty response from AI engine');
    }
    
    return JSON.parse(text) as MoodMandalaSetup;
  } catch (err: any) {
    console.error('Error in generateMandalaFromMood:', err);
    throw new Error(err.message || 'Failed to connect to Gemini API. Check your key and connection.');
  }
}
