package net.greeta.stock.common.restaurant;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class RestaurantDeletedEvent implements RestaurantEvent {

    private String id;
}
