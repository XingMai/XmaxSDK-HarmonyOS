import { Reference } from './Reference';

export enum ReferenceCameraPosition {
  FRONT = 'front',
  BACK = 'back'
}

export enum ReferenceCategoryInput {
  REFERENCES = 'references',
  PROMPT = 'prompt',
  INSTRUCTION = 'instruction'
}

@Observed
export class ReferenceCategory {
  readonly id: string;
  readonly name: string;
  readonly defaultCameraPosition: ReferenceCameraPosition;
  readonly supportedCameraPositions: ReferenceCameraPosition[];
  readonly input: ReferenceCategoryInput;
  readonly references: Reference[];
  readonly instruction: string;

  constructor(
    id: string,
    name: string,
    defaultCameraPosition: ReferenceCameraPosition,
    supportedCameraPositions: ReferenceCameraPosition[],
    input: ReferenceCategoryInput,
    references: Reference[] = [],
    instruction: string = ''
  ) {
    this.id = id;
    this.name = name;
    this.defaultCameraPosition = defaultCameraPosition;
    this.supportedCameraPositions = supportedCameraPositions;
    this.input = input;
    this.references = references;
    this.instruction = instruction;
  }

  supports(position: ReferenceCameraPosition): boolean {
    return this.supportedCameraPositions.includes(position);
  }
}
