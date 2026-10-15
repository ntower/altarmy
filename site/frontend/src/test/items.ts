import type { ItemInfo } from '../api/client'

/** An ItemInfo with every field empty, for tests to override. */
export function makeItem(overrides: Partial<ItemInfo> & Pick<ItemInfo, 'id' | 'name'>): ItemInfo {
  return {
    quality: 1,
    class_id: 0,
    subclass_name: null,
    inventory_type: 0,
    bonding: 0,
    item_delay: 0,
    container_slots: 0,
    required_level: 0,
    required_skill: null,
    required_skill_rank: 0,
    description: null,
    sell_price: 0,
    icon: null,
    armor: 0,
    dmg_min: 0,
    dmg_max: 0,
    dps: 0,
    stats: [],
    effects: [],
    ah_price: null,
    ah_sell_price: null,
    ah_quantity: null,
    ah_levels: [],
    vendor_price: null,
    market_price: null,
    median_7d: null,
    scans_7d: null,
    sale_price: null,
    sold_7d: 0,
    sold_pairs_7d: null,
    listed: null,
    seen_at: null,
    stack_size: 1,
    turn_ins: [],
    ...overrides,
  }
}

export const linen = makeItem({
  id: 1,
  name: 'Linen Cloth',
  sell_price: 13,
  ah_price: 20,
})
export const thread = makeItem({
  id: 2,
  name: 'Coarse Thread',
  sell_price: 10,
  vendor_price: 100,
})
export const robe = makeItem({
  id: 3,
  name: 'Green Robe',
  quality: 2,
  class_id: 4,
  subclass_name: 'Cloth',
  inventory_type: 20,
  bonding: 2,
  required_level: 12,
  required_skill: 'Tailoring',
  required_skill_rank: 50,
  description: 'Soft and green.',
  sell_price: 216,
  icon: 'inv_chest_cloth_39',
})
/** Lionheart Helm as the game shows it. */
export const helm = makeItem({
  id: 12640,
  name: 'Lionheart Helm',
  quality: 4,
  class_id: 4,
  subclass_name: 'Plate',
  inventory_type: 1,
  bonding: 2,
  required_level: 56,
  armor: 565,
  stats: ['+18 Strength'],
  effects: [
    {
      trigger: 'Equip',
      text: 'Improves your chance to get a critical strike by 2%.',
    },
    { trigger: 'Equip', text: 'Improves your chance to hit by 2%.' },
  ],
  sell_price: 21894,
})
/** Masterwork Stormhammer: a one-hand mace. */
export const hammer = makeItem({
  id: 12794,
  name: 'Masterwork Stormhammer',
  quality: 3,
  class_id: 2,
  subclass_name: 'Mace',
  inventory_type: 13,
  item_delay: 2800,
  dmg_min: 46,
  dmg_max: 86,
  dps: 23.57,
})
