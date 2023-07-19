import { LimitBuyCompleted, LimitBuyCreated, LimitSellCompleted, LimitSellCreated, MarketBuyExecuted, MarketSellExecuted } from '../generated/OrderBook/OrderBook'
import { LimitBuyOrder, LimitSellOrder } from '../generated/schema'
import { BigInt } from '@graphprotocol/graph-ts'

export function handleNewBuyLimitOrder(event: LimitBuyCreated): void {
  let order = new LimitBuyOrder(event.params.orderId.toHex())
  order.ownerAddress = event.params.ownerAddress
  order.price = event.params.price
  order.size = event.params.size
  order.save()
}

export function handleNewSellLimitOrder(event: LimitSellCreated): void {
  let order = new LimitSellOrder(event.params.orderId.toHex())
  order.ownerAddress = event.params.ownerAddress
  order.price = event.params.price
  order.size = event.params.size
  order.save()
}

export function handleBuyCompletion(event: LimitBuyCompleted): void {
  let id = event.params.orderId.toHex()
  let order = LimitBuyOrder.load(id)
  if (order != null) {
    order.size = BigInt.fromI32(0)
    order.save()
  }
}

export function handleSellCompletion(event: LimitSellCompleted): void {
  let id = event.params.orderId.toHex()
  let order = LimitSellOrder.load(id)
  if (order != null) {
    order.size = BigInt.fromI32(0)
    order.save()
  }
}
