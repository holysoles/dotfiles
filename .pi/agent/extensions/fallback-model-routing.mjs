export function chooseFallbackRoute(id, ctx, preferUpstream) {
  const downstream = ctx.modelRegistry.find("enmaas", id);
  const upstream = ctx.modelRegistry.find("openai", id);
  const useUpstream = preferUpstream || !downstream || !ctx.modelRegistry.hasConfiguredAuth(downstream);
  const model = useUpstream ? upstream : downstream;
  if (!model) throw new Error(`No available model for ${id}`);
  return { model, state: useUpstream || undefined };
}

export function resolveFallbackModel(id, ctx) {
  return chooseFallbackRoute(id, ctx, false).model;
}
