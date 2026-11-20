export function slug(title: string): string {
  return title.trim().toLowerCase().replaceAll(/\W+/g, '-')
}
